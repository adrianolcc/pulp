# deploy

The PULP stack as Docker Compose: `compose.yaml` with the profiles core, enterprise,
robot, robot-lite and ai, plus the Mosquitto and Grafana configuration. Use it through
the Makefile, which reads `.env` from the repo root:

```sh
cp .env.example .env     # once; replace every change-me
make up                  # core profile; waits until every service is healthy
make up PROFILES=core,enterprise
make ps                  # containers and health
make stats               # memory and CPU, sampled once
make logs SERVICE=mosquitto
make down
```

Only the core profile has services so far. The others are filled in by WP-10 (enterprise),
WP-13 to WP-17 (robot, robot-lite) and WP-18 to WP-21 (ai).

## Core services

| Service | Image | On the host | What to check |
| --- | --- | --- | --- |
| mosquitto | `eclipse-mosquitto:2.1.4-alpine` | MQTT `localhost:1883`, WebSocket `localhost:9001` | MQTT Explorer logs in with `MQTT_USERNAME` / `MQTT_PASSWORD` |
| timescaledb | `timescale/timescaledb-ha:pg17.11-ts2.32.0` | PostgreSQL `localhost:5432` | `\dx` lists `timescaledb` and `vector` |
| grafana | `grafana/grafana-oss:13.0.2` | <http://localhost:3000> | Connections → Data sources → PULP historian → Test |

Ports bind to 127.0.0.1: the Windows browser and tools reach them, the rest of the
network cannot. Image tags are pinned, so an upgrade is a deliberate change.

## Things worth knowing

- **Mosquitto users.** `mosquitto/entrypoint.sh` rebuilds the password file from `.env`
  at every start, so changing the MQTT password is: edit `.env`, then `make up`.
  Anonymous clients are refused. Topic ACLs come with WP-23.
- **The database is initialised once.** `historian/migrations` runs only on an empty
  volume; see `historian/migrations/README.md` to rebuild.
- **Grafana's admin password** from `.env` applies on the first start only. Later,
  change it in Grafana or remove the `pulp_grafana-data` volume.
- **Grafana is read-only on the historian.** It logs in as `GRAFANA_DB_USER`, which
  can only `SELECT`.
- **Offline.** Grafana's usage reports, update checks and plugin downloads and
  TimescaleDB's telemetry are switched off.

## measure/

The one-off WP-02 memory measurement: stand-ins for the enterprise and robot profiles.
Not part of the stack. See `docs/notes/wp-02-memory.md`.
