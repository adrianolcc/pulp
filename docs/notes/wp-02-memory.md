# WP-02 memory measurement

Measured on 18 Nov 2026 on the project laptop (WSL2 capped at 10 GB, Docker 29.8.2,
Compose 5.6.0). The figures feed the runtime environment table in docs/spec.md and
[ADR-002](../adr/002-robot-as-default.md).

## Method

1. Start the core profile: `make up PROFILES=core`.
2. Start the stand-ins for the heavy profiles, alongside core, so the total is what
   running every profile at once costs:
   ```sh
   docker compose -p pulp-measure -f deploy/measure/compose.yaml --env-file .env up -d
   ```
   - **enterprise:** `mboscolo/odooplm:19.0-slim-build63` (Odoo 19, all community
     OdooPLM modules, no CAD conversion stack) with `postgres:17`. First boot creates
     the database with demo data and installs `mrp` and `plm` (about 80 s).
     Odoo runs in its default threaded mode (`workers = 0`).
   - **robot:** `moveit/moveit2:lyrical-release` running
     `deploy/measure/robot_headless.launch.py`: move_group, robot_state_publisher,
     ros2_control with mock hardware, and the arm, hand and joint-state controllers
     of the MoveIt Panda example, with no RViz.
3. Load each one: log in to Odoo and open the web client and the Manufacturing
   views, then read manufacturing orders, BOMs, products, stock moves and work
   centers five times over JSON-RPC. Plan and execute three arm moves through
   MoveIt's `/move_action`.
4. Sample `docker stats` five times, 20 s apart (the min and max below). Read the
   cgroup's `memory.peak`, which is the highest usage since the container started,
   so it includes the Odoo module install and MoveIt startup. It also counts page
   cache, which the kernel gives back under pressure.
5. Remove the stand-ins:
   `docker compose -p pulp-measure -f deploy/measure/compose.yaml --env-file .env down -v`.

`make stats` prints the current figure for the running PULP containers.

## Results

| Profile | Container | docker stats (MiB) | Peak incl. page cache (MiB) |
| --- | --- | --- | --- |
| core | mosquitto | 5–6 | 11 |
| core | timescaledb | 36–37 | 46 |
| core | grafana | 124–126 | 149 |
| enterprise | odooplm | 266–267 | 286 |
| enterprise | odoo-db (postgres:17) | 148–150 | 423 |
| robot | ros (MoveIt, mock hardware) | 156 | 259 |
| **All** | | **about 740** | **about 1,170** |

Used memory of the whole WSL2 VM with everything above running: **about 2.0 GB of
10 GB**. That includes the Docker engine and the Linux kernel.

Largest processes in the robot container (RSS): move_group 103 MiB, ros2_control_node
66 MiB, the `ros2 launch` process 62 MiB, robot_state_publisher 41 MiB.

## What the numbers mean

- **These are infrastructure figures, not final ones.** The core profile has no
  simulators, gateway or services yet. A small asyncua or MQTT service in Python
  typically uses 50–100 MB, so the eleven planned Python services and the control
  room add roughly 1 GB. The real robot cell (WP-13 to WP-15) adds a cell
  controller, a behavior tree and an OPC UA server to the MoveIt process.
- **The historian is empty.** TimescaleDB's figure will grow with data and queries,
  up to its `shared_buffers` (128 MB by default) plus per-query memory.
- **Odoo in production mode costs more.** With `workers = 2` or more, each worker is
  its own process of about 150–250 MB. Threaded mode is enough for one user and the
  integration service.
- Even after these additions, the total stays well below the 10 GB WSL2 cap. The
  spec's estimates (2 GB enterprise, 1.5 GB robot, 1.5 GB core) were conservative.

## Disk

The images take about 16 GB in total: moveit2 5.95 GB, timescaledb-ha 4.21 GB,
odooplm slim 3.78 GB, grafana-oss 1.47 GB, postgres:17 0.67 GB, mosquitto 0.04 GB.
timescaledb-ha is large because it bundles pgvector and other extensions; the
smaller `timescale/timescaledb` image has no pgvector, which WP-18 needs.
