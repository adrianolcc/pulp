# ADR-001: UNS hub vs point-to-point integration

- **Status:** Accepted
- **Date:** 2026-10-13
- **Work package:** WP-01

## Context

PULP connects five simulated stations, a robot cell, a historian and event journal,
MES-lite, analytics, Odoo with OdooPLM, a production agent and a browser control room.
Something has to carry data between them.

The traditional way is point-to-point: each consumer connects to each producer it
needs. The historian polls every station, MES-lite polls them again, the ERP connector
talks to MES-lite, and so on. With *n* systems this tends towards *n²* connections,
each with its own protocol, format and failure modes. Adding a sixth station means
touching every consumer.

The alternative is a Unified Namespace (UNS): one message broker that holds the current
state of the whole plant under a single topic tree. Producers publish to it once;
consumers subscribe to what they need without knowing who produced it.

## Decision

One MQTT broker (Eclipse Mosquitto) is the UNS. Every layer publishes to it and reads
from it. The topic tree follows the ISA-95 asset hierarchy:
`pulp/paris/molding/line1/<asset>/<class>/<name>`, defined in contracts/ (WP-03).

Two links stay point-to-point, on purpose:

- **Edge gateway ↔ stations, over OPC UA.** This is the machine boundary. The gateway
  is the only component that speaks OPC UA to the machines, and it bridges to the UNS.
- **Press 2 ↔ robot interlock.** The cell handshake is time-critical and local to the
  cell, as it would be in a real plant; its outcome is still published to the UNS.

## Consequences

Good:

- Adding a station or a consumer is a configuration change; nothing else changes
  (architecture scenario "a sixth station is added by editing configuration only").
- The control room subscribes to the broker directly over WebSockets and sees
  everything live.
- Each layer can be tested alone by replaying recorded UNS traffic (`pulp-replay`).
- One place to trace a value: every message carries a `trace_id`, and hops publish
  to `pulp/_sys/trace`.

Bad, and how PULP handles it:

- **The broker is a single point of failure.** The edge gateway buffers messages
  while the broker is down (store-and-forward; I-20, ADR to come).
- **No built-in contract.** MQTT accepts any bytes on any topic. Every payload is
  validated against JSON Schemas in contracts/, and CI checks them.
- **Commands need care.** Request/response over publish/subscribe needs explicit
  `cmd` and `cmd_result` topics with correlation IDs, rather than a direct call.
- **Ordering is per topic only.** Consumers that need a global order rely on the
  `ts` from the simulation clock, not on arrival order.

## Alternatives considered

- **Point-to-point (OPC UA and REST between every pair).** Simpler for two or three
  systems; does not scale to this one, and leaves no single place to observe or
  replay traffic.
- **Kafka or Redpanda as the hub.** Better retention and replay, but heavier on a
  16 GB laptop, and browsers cannot subscribe to it directly. MQTT is also the
  established UNS protocol in industry.
- **United Manufacturing Hub.** A complete UNS platform. Studied for its data model,
  but adopting it whole would hide the parts PULP is meant to teach.
