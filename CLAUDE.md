# CLAUDE.md

PULP is an open-source simulation of a small rubber-molding line that runs on one
Windows laptop: simulated stations on OPC UA, an edge gateway, an MQTT Unified Namespace
(UNS), a TimescaleDB historian and event journal, Odoo with OdooPLM, a ROS 2 robot cell,
a production agent and a browser control room.

**The specification is [docs/spec.md](docs/spec.md).** Read "Functional analysis", "Repo
and conventions" and the section for the work package (WP-NN) you are working on before
changing anything. Decisions are recorded in [docs/adr/](docs/adr/).

## Rules

- **Never change anything in contracts/ without asking first.** The same applies to the
  UNS topic scheme and the event types. A contract change needs an ADR.
- One work package per session, on its own branch (`wp-NN-<slug>`) with one pull request.
  Do not start the next package; its checks come first.
- If code and docs/spec.md disagree, stop and ask; when a decision changes, update
  docs/spec.md in the same pull request.
- Every message and event carries `trace_id`, `ts` and `asset`. The simulation clock is
  the only time source: no `datetime.now()` or `time.time()` in simulation or service logic.
- Real protocols only (OPC UA, MQTT, Odoo's API), never mocks of them; test with the fakes
  and recorded traffic from testkit/.
- Every write from the production agent goes through the approval queue.
- Secrets live in `.env`, never in Git. A new variable goes into `.env.example` too.
- The owner is learning this stack: explain non-obvious decisions in the pull request
  description.

## Naming

"PULP" in prose and READMEs. Lowercase `pulp` everywhere else: packages, topics
(`pulp/...`), containers, paths. Python distributions are `pulp-<name>`, imported as
`pulp_<name>`. CLI tools are prefixed `pulp-`.

## Commands

| Command | What it does |
| --- | --- |
| `make setup` | First time: install the workspace and the pre-commit hook |
| `make lint` | ruff check, ruff format --check, mypy --strict per package (CI runs this) |
| `make fmt` | Apply ruff fixes and formatting |
| `make test` | Unit and contract tests (CI runs this) |
| `make up PROFILES=core,ai` | Start the stack with the given compose profiles |
| `make down` / `make logs [SERVICE=x]` | Stop the stack / follow logs |
| `make storyline-<a..f>` | Run one storyline end to end, headless |
| `uv run pytest common/tests` | Tests of one package |
| `uv add --package pulp-sim asyncua` | Add a dependency to one package |

## Layout

Python packages are uv workspace members, one per service, each with the same shape:

```
<service>/pyproject.toml      distribution pulp-<service>, depends on pulp-common
<service>/src/pulp_<service>/  code (src layout), with a py.typed marker
<service>/tests/               pytest tests for this package
```

Members: common, testkit, sim, edge, historian, mes_lite, analytics, integration,
robot_lite, onboarding, ai. A new member must be added to `[tool.uv.workspace]`,
`testpaths` in the root pyproject.toml, and `PY_PACKAGES` in the Makefile.

Not Python packages: contracts/ (interfaces), robot/ (ROS 2, built only in its container),
ui/ (React + TypeScript, Vite), scenarios/ (storyline YAML), deploy/ (Docker Compose).

## Conventions

- Python 3.12, uv, ruff, mypy in strict mode, pytest. Type every function.
- Services never import each other; shared code goes in pulp-common. Services never
  read another service's database tables.
- Test levels are pytest markers: unmarked is a unit test; `contract`, `layer` and
  `storyline` mark the others (see "Verification" in docs/spec.md).
- Datetimes are always timezone-aware (UTC).
- Conventional commits: `feat(sim): ...`, `fix(edge): ...`, `docs: ...`, `chore: ...`.
