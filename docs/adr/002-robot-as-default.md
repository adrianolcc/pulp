# ADR-002: Full ROS 2 robot cell as the default, robot-lite as the stand-in

- **Status:** Accepted
- **Date:** 2026-11-18
- **Work package:** WP-02

## Context

The robot cell exists twice behind one contract (docs/spec.md, "Stack choices"):

- **robot:** ROS 2 Lyrical with MoveIt 2 and ros2_control mock hardware, headless,
  with the cell controller and its behavior tree (WP-13 to WP-15).
- **robot-lite:** a Python stand-in that exposes the same OPC UA server, topics and
  task lifecycle, replaying cycle times recorded from MoveIt runs (WP-16).

The spec's rule is to run every profile at once, and to fall back to robot-lite if
the measured total does not fit the 10 GB WSL2 cap. It estimated about 1.5 GB for
ROS 2 with MoveIt and about 2 GB for Odoo with OdooPLM. WP-02 measured both
(docs/notes/wp-02-memory.md):

- ROS 2 with MoveIt, mock hardware, three controllers and planned moves: about
  160 MB steady and 260 MB at peak.
- Odoo with OdooPLM, Manufacturing and its PostgreSQL, under light use: about
  420 MB steady.
- Core infrastructure (Mosquitto, TimescaleDB, Grafana): about 170 MB.
- The whole WSL2 VM with all of them running: about 2.0 GB of 10 GB.

## Decision

**The robot profile (full ROS 2) is the default** for storylines A and E and for
`make up` with every profile. Memory is not a constraint: even with the planned
services added (roughly 1 GB more), all profiles together stay far below the cap.

**robot-lite stays, with a narrower job:**

- **CI and fast tests.** Automated tests that need a robot but are not about the
  robot use robot-lite. That is faster and saves pulling a 6 GB image on every run.
- **Development of other layers.** Work on the edge, MES-lite or the agent does not
  need MoveIt running.
- **The architecture check.** "robot swaps for robot-lite with no change elsewhere"
  proves the contracts are complete. The contract tests shared by both are what
  enforce it.

## Consequences

- WP-13 to WP-15 are on the critical path of storylines A and E, as planned. WP-16
  still gets built, but it is no longer a memory fallback.
- The first `make up PROFILES=...,robot` pulls a large image (moveit2 is about
  6 GB on disk); after that, startup takes seconds.
- No memory limits are set on containers yet. Revisit when the real services exist
  (phase 2) and again before v1.0, with the soak test (WP-23).
- If a later measurement with the full stack gets near the cap, this ADR is
  superseded, not edited.

## Alternatives considered

- **robot-lite as the default, ROS 2 only for storyline A.** Lighter and faster to
  start, but the robot view, the cycle times and the arbitration would come from
  a replay rather than from the real cell controller. The measurement removed the
  only reason for it.
- **Decide later, after WP-13.** The spec asks for the decision in phase 0, and
  waiting would not change the infrastructure figures this decision depends on.
