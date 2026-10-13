# PULP

Industrial Software and Process Simulation.

PULP is an open-source simulation of a small rubber-molding line that runs on one
laptop: simulated machines on OPC UA, an edge gateway, an MQTT Unified Namespace,
a historian and event journal, an ERP and PLM, a ROS 2 robot cell and a production
agent, all visible live in a browser control room.

Everything is simulated behind real industrial protocols. There is no real hardware
and no functional safety: safety signals are simulated.

- Specification and roadmap: [docs/spec.md](docs/spec.md)
- Architecture decisions: [docs/adr/](docs/adr/)

## Quick start

Requires uv, GNU make and Docker (see WP-00 in the spec).

```sh
make setup          # install the Python workspace and the pre-commit hook
cp .env.example .env
make lint test      # what CI runs
make help           # every command
```

## License

Apache-2.0. Odoo and OdooPLM run as unmodified containers under their own licenses.
