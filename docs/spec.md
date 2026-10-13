# PULP — Industrial Data Stack: Scope & Roadmap

Oct 13, 2026 · @Adriano

## Changes

- **13 Oct 2026:** project renamed from Brownfield (working name) to **PULP**. Repo `pulp`, folder `~/pulp`, UNS topic root `pulp/`, CLI tools `pulp-record`, `pulp-replay` and `pulp-fault`. Decided: GPU memory (RTX 3050, 6 GB) and the embedding model (`nomic-embed-text`). WP-00 mostly done; setup notes added under WP-00. Ranges corrected to I-01 to I-25 and storylines A to F.

## Purpose

**PULP** is an open-source simulation of a small rubber-molding line that runs on one Windows laptop. It connects simulated machines, an edge gateway, a Unified Namespace (UNS), a historian and event journal, an ERP and PLM, a ROS 2 robot cell and a production agent. A browser control room shows all of it live.

The system does six things:

- **Produces parts.** Five simulated stations and a robot cell run a causal process: upstream conditions change downstream quality.
- **Records everything.** Every value, state change, alarm, order, part and robot task is captured with its order and part revision attached.
- **Closes the enterprise loop.** Orders and part revisions flow from Odoo and OdooPLM down to the machines; production results flow back up.
- **Corrects drift.** A process advisor turns detected drift into recipe corrections, inside the process window released in PLM, then checks that each correction actually reduced scrap and rolls it back if not.
- **Shares the robot.** The robot does its production work and also accepts extra tasks from the production agent. The system computes and shows what each extra task costs the line.
- **Answers questions.** The production agent answers questions such as "what was produced between 14:00 and 15:00, and were there errors?" by querying the journal, Odoo and OdooPLM, with a source for every fact.

Ground rules: real industrial protocols, never mocks of them; open-source components only; everything runs offline except the language model API; every write from the agent waits for human approval; one command starts the stack.

### Using this document with Claude Code

This document is the project specification. Keep it in the repo as `docs/spec.md`, and update it when a decision changes. Each work package (WP-00 to WP-28) is sized for one Claude Code session. Interactions are numbered I-01 to I-25 and storylines A to F, so prompts and tests can reference them.

Start each session with a prompt like this:

```
Read docs/spec.md, especially "Functional analysis" and the section for WP-NN.
Implement WP-NN as described. Respect the contracts in contracts/.
Write tests for the interactions listed under its "Verify" line.
Do not change a contract, the topic scheme or the event types without asking me.
Explain non-obvious decisions in the pull request description; I am learning this stack.
```

## Reference architecture

Five layers follow the Purdue model, and one MQTT broker serves as the Unified Namespace (UNS) that every layer publishes to and reads from. Nothing talks point-to-point except the edge gateway to the machines, and the interlock between press 2 and the robot inside their cell.

*Diagram: PULP architecture · 6 layers around one MQTT hub (in the original document).*

Data moves four ways:

- **Up:** a machine value changes, the edge gateway's OPC UA subscription picks it up and publishes it to the UNS with a trace ID. The historian, event journal, MES-lite and analytics consume it, and good and scrap counts flow on to Odoo as confirmations. The trace ID lets the control room follow one value through every hop.
- **Down:** a manufacturing order released in Odoo carries a part revision from OdooPLM. The integration service turns it into a recipe command on the UNS; the edge gateway writes it to the machine with an OPC UA method call.
- **Robot requests:** the production agent proposes an extra robot task with an impact estimate. Once you approve it, the command travels through the UNS to the cell controller, which runs it at the next safe point between press cycles.
- **Questions:** the production agent reads every system through fixed tools. It writes only through the approval queue.

### Stack choices

| Layer | Pick | Why | Fallback |
| --- | --- | --- | --- |
| Host | Windows 11 laptop; Docker Desktop with the WSL2 backend | Every service runs as a Linux container; the control room opens in the Windows browser | None needed |
| Machine simulation and OPC UA | Python 3.12 with [asyncua](https://pypi.org/project/asyncua/) | Real OPC UA server and client in the same language as most of the stack | open62541 (C), node-opcua |
| Robot cell | [ROS 2 Lyrical Luth](https://discourse.openrobotics.org/t/ros-2-lyrical-luth-released/55021) + [MoveIt 2](https://github.com/moveit/moveit2) + ros2_control mock hardware, headless in an Ubuntu 26.04 container | Current LTS, supported until May 2031; no RViz or Gazebo, because the control room draws the robot | robot-lite: a Python stand-in with the same contract |
| Robot task logic | Behavior tree (py_trees or BehaviorTree.CPP) in the cell controller | The usual ROS 2 way to sequence skills and handle interruptions | A plain state machine |
| Robot data model | [OPC UA Robotics, OPC 40010-1](https://opcfoundation.org/developer-tools/specifications-opc-ua-information-models/opc-unified-architecture-for-robotics/), including its 2025 task-control state machines | The standard way a robot exposes identity, state and task control | Custom nodes |
| UNS broker and payload | Eclipse Mosquitto with TCP and WebSocket listeners; JSON messages validated against JSON Schemas | The browser subscribes directly; schemas are checked in CI | Sparkplug B as a stretch goal |
| Historian, event journal, MES-lite | TimescaleDB (PostgreSQL) with pgvector | One Postgres holds time series, the journal, genealogy and document embeddings | InfluxDB 3 |
| ERP | Odoo 19 Community, Manufacturing app | A real ERP with manufacturing orders, BOMs and work centers, scriptable over its API | ERPNext |
| PLM | [OdooPLM](https://github.com/OmniaGit/odooplm) on the same Odoo | Open source; engineering BOM separate from manufacturing BOM; revision lifecycle; Docker image with demo data; ships its own MCP server | Odoo's own PLM is Enterprise-only |
| Asset model (stretch) | [Eclipse BaSyx](https://pkg.go.dev/github.com/eclipse-basyx/basyx-go-components) (Asset Administration Shell) | MIT-licensed, runs in Docker Compose | A JSON manifest (v0.3) |
| Production agent | An API language model with tool calling; fixed, typed tools served over MCP | Reliable multi-step tool use without loading the laptop | A local model through Ollama, as an offline mode |
| Document search (RAG) | `nomic-embed-text` through Ollama on the RTX 3050 (6 GB); pgvector | Embedding models are small; documents stay on the laptop | Embeddings on the CPU |
| Control room | React + TypeScript (Vite), MQTT over WebSockets, React Three Fiber and urdf-loader for 3D; Grafana for trends | Line, data flow, ask and approval views in one app | 2D SVG line view only |
| Ops | Docker Compose with profiles and one network per Purdue zone; GitHub Actions; Prometheus | One command to run; segmentation you can show | k3s as a stretch goal |
| Process correction | Python: feedforward rules and an EWMA run-to-run controller (v1.0); a scikit-learn or LightGBM defect model with a SciPy optimizer (v1.1) | Explainable control first, ML second, both compared on the same storyline | Rules only |

### Decisions to write up as ADRs

- UNS hub vs point-to-point integration.
- JSON with schemas vs Sparkplug B payloads.
- One PostgreSQL for everything vs specialized stores.
- Event journal design: what counts as an event, and which IDs every event carries.
- Production agent: fixed tools vs free-form SQL vs pure RAG.
- Robot task arbitration: priorities, safe points, pre-emption.
- Full ROS 2 vs robot-lite behind the same contract.
- How the agent writes safely: approval queue, idempotency keys, audit log.
- Store-and-forward at the edge when the broker is down.
- Process correction: where the process window lives, step limits, and when automatic mode is allowed.

### What already exists, and how to use it

Each slice of this exists somewhere; the combination does not, as far as these searches found. [United Manufacturing Hub](https://www.umh.app/insight/united-manufacturing-hub-relicensed-to-apache-2-0) is an open-source UNS platform. Phoenix Contact's [MORYX](https://github.com/phoenixcontact/moryx-framework) is a digital-twin framework with ERP and PDM integration. SINTEF's [SINDIT](https://github.com/SINTEF-9012/SINDIT) runs a digital twin on a training factory. Several MCP servers already expose OPC UA to LLMs, such as [opcua-mcp](https://enterprisedna.co/directories/mcp/kukapay-opcua-mcp) and [machina-ai](https://pypi.org/project/machina-ai/). Borrow from them instead of competing: study UMH's data model, and plug OdooPLM's MCP tools straight into your agent. Your contribution is the robot-onboarding story and the cross-system agent with approvals, in one teachable repo.

## Runtime environment

Everything runs on one Windows 11 laptop with an Intel Core i7 (13th gen), 16 GB of RAM and an RTX 3050 laptop GPU with 6 GB of dedicated memory. Docker Desktop runs every service as a Linux container inside WSL2. The control room, UaExpert and MQTT Explorer run on Windows.

| Component | Runs where | Estimated RAM |
| --- | --- | --- |
| Windows, browser, desktop tools | Windows | 5–6 GB |
| WSL2 memory cap, set in .wslconfig | WSL2 | 10 GB maximum |
| Odoo 19 + OdooPLM + their PostgreSQL | Container, profile enterprise | About 2 GB |
| ROS 2 + MoveIt, headless | Container, profile robot | About 1.5 GB |
| Broker, TimescaleDB, simulators, gateway, services, control room | Containers, profile core | About 1.5 GB |
| Production agent and tool server | Container, profile ai | Under 0.5 GB; the model runs through the API |
| Embedding model (`nomic-embed-text`) | Ollama on Windows, RTX 3050 | No system RAM; about 320 MB of GPU memory, measured |

These are estimates. WP-02 measures the real numbers with docker stats and records them in this table.

| Profile | Contains | Needed by storylines |
| --- | --- | --- |
| core | Mosquitto, TimescaleDB, Grafana, station simulators, edge gateway, journal and historian writers, MES-lite, analytics, control room | All |
| enterprise | Odoo with OdooPLM, integration service | B, C, D, E, F |
| robot | ROS 2 container, cell controller, onboarding service | A, E |
| robot-lite | Python robot stand-in with the same contract, onboarding service | Any, when memory is short |
| ai | Tool server, approval queue, impact estimator, production agent, document indexer | C, D, E, F |

Rules for this machine:

- **Aim to run all profiles at once.** If the measured total does not fit, start robot-lite instead of robot. The stand-in exposes the same OPC UA server, topics and task lifecycle, with cycle times recorded from MoveIt runs, so the line view never loses the robot.
- **No RViz and no Gazebo.** The control room renders the arm from its URDF and live joint states.
- **Keep the repo inside WSL2** (`~/pulp`), not on the C: drive; bind mounts from the Windows filesystem are much slower.
- **Containers reach Ollama on Windows** at `host.docker.internal:11434`. Check this in WP-18; if a container cannot reach it, Ollama may need to listen on all interfaces (`OLLAMA_HOST=0.0.0.0`).
- **GPU:** the RTX 3050 has 6 GB of dedicated memory; Ollama uses it through CUDA and Optimus wakes the card on demand. The Intel Iris GPU borrows system RAM and is not used. `ollama ps` should show 100% GPU.

## The simulated factory

The line makes a molded rubber part in five stations, and the scripted storylines exercise every layer. Each station is its own OPC UA server, so the edge gateway faces the same mess of separate devices a real brownfield site has.

| Station | What it simulates | Main signals | Faults you can inject |
| --- | --- | --- | --- |
| Internal mixer | Batch mixing of the compound | Rotor speed, ram pressure, batch temperature, mixing energy, dump temperature | Slow cooling loss, so batch temperature creeps up |
| Extruder | Preform production | Screw speed, melt pressure, die temperature, preform weight | Weight scatter |
| Curing presses 1 and 2 | Molding and vulcanization | Platen temperature, cure time, mold pressure, cycle state | Heater zone failure; cure time changed by an ECO |
| Robot cell | Unloading press 2, placing parts on the inspection conveyor | Cell state, cycle time, gripper status, handshake signals | Missed grip, handshake timeout, emergency stop |
| Vision inspection | Pass or fail per part | Result, defect class (flash, underfill, porosity) | None; it reports what upstream caused |

Keep the process model simple but causal. Cure quality depends on temperature and time, and compound history follows each part, so an upstream drift shows up as defects two stations later. That causality is what makes the AI questions interesting.

The robot and press 2 talk through a classic interlock handshake, written as two state machines: the press signals cycle done and mold open; the robot requests entry; the press grants it; the robot picks, reports clear; the press starts the next cycle. Timeouts and faults on each step are where integration bugs live.

The robot also has a second job. Besides unloading press 2 every cycle, it accepts extra tasks from the production agent: moving parts to the audit table, clearing a jam, changing its gripper. Every extra task takes time from press 2, so the line's output, OEE and order completion dates react to it. "Robot tasks and arbitration" below defines how.

### Storylines and acceptance

Each storyline is a scripted scenario in `scenarios/`, runnable headless with `make storyline-<letter>` and from the control room. A storyline passes when its listed interactions pass.

| Storyline | Trigger | Expected behavior | Accept when |
| --- | --- | --- | --- |
| A. Onboard a robot cell | Start the robot profile while press 2 is unloaded by hand | The cell publishes its self-description, gets mapped into the asset tree and topics, runs commissioning checks (comms, handshake round trip, cycle time vs takt, safety signals, gripper test) and receives a readiness score with a punch list | All checks pass on a healthy cell, and each of three injected faults fails its matching check (I-16) |
| B. Engineering change hits the floor | Release revision C of the part in OdooPLM, with a longer cure time | The next order runs rev C; the recipe reaches the press; cycle time and throughput change; genealogy separates rev B and rev C parts | No rev C order part is made with the rev B recipe (I-05, I-06, I-09) |
| C. Drift to root cause | Inject a slow cooling loss on the mixer | Batch temperature creeps; a drift event fires before underfill scrap peaks; asked about scrap, the agent links it to the mixer batches and drafts a maintenance work order that waits for approval | Drift detected before the scrap threshold; the answer cites journal events and batches (I-15, I-17, I-18) |
| D. Ask the factory | Questions typed in the Ask view | Answers about production, errors, orders and revisions, for any time window, with sources | The evaluation set reaches its target pass rate; every number traces to a tool result (I-17) |
| E. Robot pulled off the line | During a busy order, the agent requests five audit parts | An impact estimate (blocked cycles, lost parts, order delay) appears; you approve now, schedule for the next window, or reject; the robot runs the task at a safe point; press 2 blocks; OEE records the loss as robot_reassigned; the order's expected finish moves in Odoo | Predicted and measured loss agree within one press cycle; no task runs without approval; the journal explains the loss (I-12, I-13, I-14, I-18) |
| F. Drift corrected | The same mixer cooling loss as storyline C, with the process advisor on | Feedforward adjusts cure time for hot batches; run-to-run trims as inspection results arrive; you approve each correction; scrap returns toward baseline. When the drift grows beyond the PLM process window, the advisor stops correcting and proposes a change order and a maintenance work order instead | Scrap stays under its threshold where the uncorrected run of storyline C exceeded it; no recipe outside the window reaches a machine; a deliberately bad correction is rolled back (I-21 to I-24) |

## Functional analysis

Every interaction in the system has an ID, is recorded as one or more journal events, and has a check that proves it works. Tests, storylines and the control room are all built from this section.

### Actors

| Actor | Role |
| --- | --- |
| Station simulators (mixer, extruder, press 1, press 2, vision) | Run the process; expose state, values and methods over OPC UA |
| Robot cell (ROS 2 robot and cell controller) | Executes skills; runs the press 2 interlock; owns the robot task queue |
| Edge gateway | The only bridge between field and UNS; reads by subscription, writes recipes and commands |
| UNS broker | Carries every message between layers |
| Historian and journal writers | Persist telemetry and events; produce hourly and shift summaries |
| MES-lite | Order tracking, genealogy, OEE with reason codes, order ETA |
| Integration service | Moves orders and recipes down from Odoo and OdooPLM, confirmations back up |
| Odoo ERP | Manufacturing orders, BOMs, work centers, confirmations, expected finish dates |
| OdooPLM | Parts, revisions, change orders, engineering documents, recipe parameters per revision |
| Analytics | Drift detection |
| Onboarding service | Commissions new cells |
| Production agent | Answers questions; proposes actions, including extra robot tasks |
| Approval queue | Holds every agent write until the operator decides; keeps the audit log |
| Operator (you) | Starts storylines, injects faults, approves or rejects, asks questions |
| Control room | Shows the line, the data flow, answers and approvals |
| Process advisor | Proposes recipe corrections inside the PLM process window, verifies their effect, rolls them back when they fail |

### Interactions to track and verify

| ID | Interaction | Recorded as | Verify |
| --- | --- | --- | --- |
| I-01 | A station value changes; the gateway's OPC UA subscription publishes it to the UNS with a trace ID | Telemetry message | Change-to-UNS latency under 1 s at p95; same value at both ends |
| I-02 | Telemetry reaches the historian | Historian row | Rows written equal messages published over a 10-minute run |
| I-03 | A station or the robot changes state | state_changed | Every transition recorded once, in order, and allowed by the state model |
| I-04 | An alarm is raised and later cleared | alarm_raised, alarm_cleared | Every raise has one clear or is still active; durations computed |
| I-05 | Odoo releases a manufacturing order; the integration service sends the recipe; the gateway calls LoadRecipe | order_released, recipe_loaded | Recipe on the machine equals the parameters of the PLM revision |
| I-06 | A press finishes a part | part_produced | Every part carries serial, order, part revision, mixer batch, press and cure profile |
| I-07 | Vision inspects a part | part_inspected | Exactly one result per produced part |
| I-08 | Good and scrap counts are confirmed to Odoo | confirmation_sent | Odoo totals equal journal totals, even after forced duplicate sends |
| I-09 | OdooPLM releases a new revision through a change order | eco_approved, revision_released | No part of a new order is made with the old revision's recipe |
| I-10 | Press 2 and the robot run the interlock handshake | handshake_step per step | Steps in the allowed order; a timeout raises an alarm; step durations stored |
| I-11 | The robot runs a skill | robot_task_started, robot_task_finished | Skill durations add up to the robot cycle time |
| I-12 | The production agent requests an extra robot task | robot_task_requested, approval_requested | No task reaches the robot without approval; every request reaches a final state |
| I-13 | The cell controller schedules or rejects an approved task | robot_task_scheduled, robot_task_rejected | The robot never leaves press 2 outside a safe point |
| I-14 | Press 2 waits because the robot is busy elsewhere | press_blocked with reason robot_reassigned, order_eta_changed | Predicted and measured loss agree within one press cycle; Odoo shows the new expected finish |
| I-15 | Analytics detects drift | anomaly_detected | In storyline C, detection comes before the scrap rate passes its threshold |
| I-16 | A new cell is onboarded | cell_registered, check_passed, check_failed, readiness_scored | Each injected fault fails its matching check |
| I-17 | The operator asks a question | question_asked, tool_called, answer_given | Every number in the answer matches a tool result; evaluation pass rate tracked |
| I-18 | An agent action is approved or rejected | approval_decided, action_executed | A rejected action changes nothing; the audit log is complete |
| I-19 | The control room follows one message through the hops | trace_hop messages | One trace ID visible at station, gateway, broker, historian and journal, with timestamps |
| I-20 | The broker is down for 10 minutes | gateway_buffering, gateway_replayed | No messages lost; order preserved |
| I-21 | The process advisor computes a correction from upstream data (feedforward) or recent results (run-to-run) | correction_proposed, approval_requested | Every proposal states its inputs, its predicted effect and the process window it respects |
| I-22 | A needed correction would leave the released process window | process_window_exceeded, eco_proposed | No recipe outside the window reaches a machine; a change order draft appears in OdooPLM |
| I-23 | An approved correction is applied to the machine | correction_applied, recipe_loaded | Applied only at a batch boundary; the machine holds exactly the approved values; genealogy records them per part |
| I-24 | The correction's effect is checked after N parts | correction_verified or correction_rolled_back | Predicted and measured scrap compared; a correction that made results worse is rolled back automatically |
| I-25 | The ML defect model is retrained and considered for promotion | model_trained, model_promoted | A new model replaces the current one only if it beats it on held-out runs and in shadow mode |

### Event journal

One append-only table, `journal_events`, holds every event. Its fixed fields make any question answerable by time, asset, order or part.

| Field | Meaning |
| --- | --- |
| event_id | UUID |
| ts | Event time from the simulation clock, in UTC |
| type | One of the event types below |
| asset | ISA-95 path, for example paris/molding/line1/press2 |
| order_id | Odoo manufacturing order, when one is running |
| part_number, part_rev | The part and its PLM revision |
| serial | Part serial, on part events |
| trace_id | Links the event to the messages that caused it |
| source | The service that wrote it |
| payload | Type-specific JSON, validated against its schema |

Event types, defined once in `contracts/` and generated for Python and TypeScript:

- **Production:** order_released, order_started, order_finished, recipe_loaded, part_produced, part_inspected, confirmation_sent, order_eta_changed
- **States and alarms:** state_changed, alarm_raised, alarm_cleared, press_blocked, press_unblocked
- **Robot:** handshake_step, robot_task_requested, robot_task_scheduled, robot_task_started, robot_task_finished, robot_task_failed, robot_task_rejected
- **Engineering:** eco_proposed, eco_approved, revision_released
- **Process correction:** correction_proposed, correction_applied, correction_verified, correction_rolled_back, process_window_exceeded, model_trained, model_promoted
- **Analytics and onboarding:** anomaly_detected, cell_registered, check_passed, check_failed, readiness_scored
- **Agent and approvals:** question_asked, tool_called, answer_given, approval_requested, approval_decided, action_executed
- **Edge health:** gateway_buffering, gateway_replayed

The journal writer also produces a plain-text summary per hour and per shift. These summaries are indexed for document search, so vague questions such as "anything unusual last night?" have something to retrieve.

### Production agent

The agent answers from fixed, typed tools; document search (RAG) is one tool among them, used for text such as procedures and notes. Tools return facts; the model only selects tools, links results and phrases the answer.

| Tool | Kind | Returns |
| --- | --- | --- |
| events(window, asset?, type?) | Read | Journal events |
| production_summary(window, line?) | Read | Parts made, good and scrap, by order and revision |
| timeseries(tag, window, step) | Read | Historian values |
| genealogy(serial) | Read | The part's full history |
| order(order_id) | Read | Odoo order: product, quantity, due date, status, expected finish |
| part_revision(part, rev) | Read | OdooPLM: BOM, recipe parameters, change orders, documents |
| robot_status() | Read | Robot mode, current task, queue |
| estimate_robot_task_impact(task, when) | Read | Blocked cycles, lost parts, order delay |
| search_docs(query, filters?) | Read, RAG | Passages from procedures, notes, maintenance logs, PLM documents and shift summaries |
| correction_history(window, asset?) | Read | Proposed, applied and rolled-back corrections with their measured effect |
| request_robot_task(task, when) | Write, needs approval | A pending approval with its impact estimate |
| create_work_order(asset, description) | Write, needs approval | A pending approval |
| hold_lot(batch, reason) | Write, needs approval | A pending approval |

Answer rules:

- Every number comes from a tool result and links to its source: an event, an order, a revision or a document.
- Relative times ("this morning", "14:00 to 15:00") are resolved to an explicit window, shown in the answer.
- No answer without at least one tool call. When the data does not cover the question, the agent says so.
- Writes never execute directly; they create approvals.

Worked example. Question: *"What was produced on press 2 between 14:00 and 15:00, and were there errors?"*

- production_summary and events for that window on press 2
- order for the order found in the events
- part_revision for the part revision on those parts
- search_docs for the procedure matching the alarm types found

Expected answer shape: *"Between 14:00 and 15:00, press 2 made 38 parts for order MO/0042 (part SEAL-12, rev C): 37 good, 1 scrap for underfill at 14:51. One alarm: a handshake timeout at 14:22, recovered in 40 s. Rev C was released last week by change order ECO-007 with a longer cure time; the underfill procedure says to check platen temperature first."* Each figure links to the record it came from.

### Robot tasks and arbitration

The robot serves the line first. Extra tasks run only at safe points, and only after you approve them.

Skills, each a ROS 2 action: unload_press, place_on_conveyor, move_part_to_audit, clear_jam, change_gripper, go_home. A behavior tree sequences them for the production cycle and for each extra task.

| Priority | Task class | Example |
| --- | --- | --- |
| 1 | Safety stop | Emergency stop; pre-empts everything |
| 2 | Production cycle | Unload press 2, place on the conveyor |
| 3 | Approved extra task with a deadline | Move five parts to the audit table |
| 4 | Maintenance task | Change the gripper, clear a jam |

Arbitration rules:

- The robot leaves press 2 only after robot_clear and before the next cycle_done: that interval is the safe point.
- An extra task that fits in the spare time of one press cycle runs at once. Otherwise press 2 blocks for the overrun, with reason robot_reassigned.
- Before approval, the impact estimator shows blocked cycles, lost parts and the order's new expected finish, for "now" and for the next changeover or idle window.
- The operator chooses: run now, run at the next window, or reject.
- A safety stop pre-empts any task. An interrupted extra task fails explicitly and can be requested again.

*Diagram: extra robot task lifecycle · 9 states, one human gate (in the original document).*

Every state change in this lifecycle is a journal event (I-12, I-13), so the journal can always explain why a task ran, waited or never happened.

### Process correction

The process advisor turns detected drift into recipe corrections, inside limits that engineering has released in PLM, and checks that each correction actually helped. It works at three levels of increasing sophistication.

| Level | How it decides | Example | Release |
| --- | --- | --- | --- |
| Feedforward | A known relation between an upstream measurement and the right downstream setting | A mixer batch arrives hotter than nominal; the press adjusts cure time for the parts made from that batch, by a calibrated amount | v1.0 |
| Run-to-run (EWMA) | Compares each batch's results with the target and moves the next recipe by a fraction of the error | Underfill rising over three batches on press 2; the platen temperature takes one small step | v1.0 |
| ML model plus optimizer | A defect model learned from journal data predicts scrap for any setting; an optimizer picks the settings that minimize predicted scrap and cycle time | Settings chosen per batch from its temperature, mixing energy and preform weight | v1.1 |

Rules:

- **PLM is the authority.** Each released revision carries a process window (minimum, nominal and maximum for cure time, platen temperature and the other settings) in its recipe attachment. Corrections stay inside it.
- **Leaving the window is an engineering change, not a correction.** The advisor records process_window_exceeded and drafts a change order in OdooPLM instead of touching the machine.
- **Small, slow steps.** One change per N batches, a maximum step size, a dead band that ignores noise, and one parameter at a time in run-to-run mode, so the effect of each change can be attributed.
- **Approval by default.** Corrections go through the same approval queue as robot tasks, with the predicted scrap reduction and cycle-time cost. An automatic mode exists only inside a narrower band, as a switch you turn on deliberately.
- **Verify, then keep or roll back.** After N parts the advisor compares predicted with measured scrap and rolls the correction back if results got worse.
- **Traceable per part.** Genealogy records the recipe values each part actually received, not just the nominal recipe.

#### What closed-loop correction implies in real plants

- **Change control.** In automotive supply chains (IATF 16949) and other regulated industries, process parameters are frozen in a control plan agreed with the customer; changing them outside it needs formal approval. The PLM window models that boundary: inside is control, outside is an engineering change.
- **Measurement lag.** Quality results arrive after the parts are made, sometimes hours later from a lab. Every correction acts on parts already in progress, which is why small, slow steps beat aggressive ones.
- **Overcorrection.** A controller that reacts to noise makes the process worse and can oscillate. Dead bands and gain tuning matter more than model sophistication.
- **Correction hides causes.** When the drift has a physical root cause, such as the mixer's cooling loss, correcting downstream masks it. The advisor must still raise a maintenance work order; correction buys time, it does not fix the mixer.
- **Correlation is not cause.** A model trained on plant history also learns what operators habitually did, not only physics. Designed experiments and shadow mode guard against learning the wrong lesson.
- **Traceability decides feasibility.** Corrections only work when each part's result links to the exact settings it received. Many real plants lack this genealogy, and that is often the first project before any ML.
- **Trust.** Operators ignore recommendations they cannot check. Explanations, the approval step and a visible track record of verified corrections are what make a system like this get used.
- **Model drift.** Raw material lots, seasons and tool wear change the process. Models need monitoring, retraining and explicit rules for promoting a new version.

### Control room

One browser app, subscribed to the UNS over WebSockets, is the main way to see and drive the simulation. Grafana stays for engineering trends.

| View | Shows | First release |
| --- | --- | --- |
| Line | Stations and robot with state colors, part counts and active alarms; later the robot's mode and task queue, and press 2 blocked | v0.1 in 2D; 3D in v1.0 |
| Data flow | The architecture drawn live: message dots travel each hop; click one to see its payload and per-hop timestamps by trace ID (I-19) | v0.1 |
| Scenarios | Buttons to start storylines A to F and inject each fault | v0.1 |
| Orders and revisions | The running order per station, its progress and expected finish, and the part revision badge | v0.2 |
| Robot and onboarding | Robot mode, current task, queue, handshake step; readiness score and punch list | v0.3 |
| Ask | Question box; the tool calls made; the answer with clickable sources | v1.0 |
| Approvals | Pending agent actions with impact estimates; approve now, schedule, or reject | v1.0 |
| Corrections | Proposed corrections with predicted effect; each setting shown against its PLM process window; scrap before and after each correction | v1.0 |
| Health | Every interaction check from I-01 to I-25 as green or red, live; service heartbeats; latency per hop | v0.1 |

## Verification

Every layer is debugged alone, against fakes and recorded traffic, before it meets the others. Assembled tests confirm that layers fit; they are never where debugging happens. When an assembled test fails, the trace ID shows the last hop that saw the message, and that layer is then reproduced alone with the same recorded traffic.

### Testing each layer alone

| Layer | Tested with | Stands in for its neighbours | Gate before moving on |
| --- | --- | --- | --- |
| Stations (simulation and OPC UA servers) | pytest and an asyncua test client | Nothing needed: stations have no upstream | Values, states and methods correct at the source; I-03 and I-04 visible on the server |
| Edge gateway | Real station servers or the fake OPC UA server, and a real broker | Fake OPC UA server playing a scripted scenario | I-01 latency, I-20 broker outage, commands reach the right method |
| UNS contracts | Schema validation of recorded traffic | Recorded UNS traffic files | Every recorded message valid; invalid samples rejected |
| Historian and journal writers | Recorded traffic replayed into the broker, a real database | Replay tool instead of stations and gateway | I-02 counts, I-03 ordering, I-04 pairing |
| MES-lite and analytics | Golden journal snapshots | Saved journals of seeded runs | I-06, I-07, I-15; OEE recomputed from raw events matches |
| Integration service | A real Odoo container and a fake UNS | Scripted UNS publisher and consumer | I-05, I-08 with forced duplicates, I-09 |
| Robot cell | ROS 2 with mock hardware | Fake press 2 OPC UA server running a scripted handshake, including timeouts | I-10, I-11, I-13; contract tests shared with robot-lite |
| Process advisor | Golden journal of a drift run | Replayed journal; fake approval queue | I-21 to I-24 offline, before it ever touches a machine |
| Tool server and agent | A seeded database snapshot | Recorded tool results for agent tests | Tool tests; I-17, I-18; make eval |
| Control room | Recorded traffic replayed to the browser | Replay tool instead of the whole stack | Playwright smoke tests: each view renders and updates |

The test kit (WP-27) provides the shared pieces:

- **Record and replay.** `pulp-record` captures UNS traffic during any run to a JSON Lines file; `pulp-replay` plays it back at real or accelerated speed. Every storyline run leaves recordings that become fixtures for the layers downstream.
- **Fakes.** A configurable fake OPC UA server, a fake press 2 for the robot, a fake UNS publisher and consumer, a fake approval queue.
- **Golden datasets.** Seeded storyline runs saved as journal snapshots, with their expected results.
- **Invariant queries.** One SQL check per interaction, written once and reused by the tests, the storyline runs and the live watchdog.

### Test levels

| Level | What it catches | When it runs |
| --- | --- | --- |
| Unit tests | Logic errors in process models, state machines, controllers | Every commit, in seconds |
| Contract tests | Services disagreeing on messages; robot and robot-lite diverging | Every commit |
| Layer tests | A layer misbehaving against its contracts, with fakes around it | Every commit touching that layer: `make test-layer LAYER=<name>` |
| Storyline tests | Layers that pass alone but do not fit together | Before every merge and release: `make storyline-<letter>` |
| Fault, soak and load tests | Fragility under failure, over time and at scale | Before every release (WP-23) |

### Checks while it runs

The watchdog (WP-28) runs the invariant queries continuously against the live journal and publishes the results. The control room's Health view shows I-01 to I-25 as green or red, service heartbeats and latency per hop. Tests prove a release works; the watchdog shows that the running system still does.

Targets for a smooth run:

- Tag change to UNS in under 1 s at p95
- Zero messages lost through a 10-minute broker outage
- Memory inside the WSL2 budget measured in WP-02
- Every check green through an 8-hour shift at accelerated time
- Full stack running in under 5 minutes from `make up`
- No unhandled errors in any service log during a storyline

### Architecture scenarios

The architecture is good if these hold. Each one is tested or reviewed at the end of the phase that makes it possible.

| Scenario | Proves |
| --- | --- |
| A sixth station is added by editing configuration only | The asset tree and UNS decouple the stations from everything else |
| robot swaps for robot-lite with no change elsewhere | The contracts are complete |
| Odoo could be replaced by changing only the integration service | The ERP is isolated behind one service |
| The broker is down for 10 minutes and nothing is lost | The edge is resilient |
| A misbehaving agent still cannot change anything without approval | The safety boundary holds |
| A service reading another service's database is caught | Dependency rules hold, enforced by lint and Docker network separation |

At the end of each phase:

- Re-read the ADRs and note whether each decision still looks right.
- Keep a pain log of everything that was harder than it should have been; repeated pain points at the architecture.
- Run a fresh-eyes review: a new Claude Code session that has never seen the code reads `docs/spec.md` and the repo and lists where they disagree.

## Scope and releases

Five releases; v1.0 lands around 7 March 2027 and v1.1 around 28 March, assuming about 15 hours a week from 19 October and a lighter week over the holidays. A release ships only when its interaction checks pass.

| Release | Target | Contents | Ships when |
| --- | --- | --- | --- |
| v0.1 Data pipe | 29 Nov 2026 | Five stations on OPC UA, edge gateway with store-and-forward, UNS, historian, event journal, drift detection, control room (2D line, data flow, scenarios) | Storyline C's drift is detected; I-01 to I-04, I-15, I-19 and I-20 pass |
| v0.2 Enterprise loop | 13 Dec 2026 | Odoo and OdooPLM, integration service, MES-lite (genealogy, OEE with reason codes, ETA), orders and revisions view | Storyline B passes; I-05 to I-09 pass |
| v0.3 Robot cell | 17 Jan 2027 | ROS 2 cell (skills, behavior tree, handshake), cell controller with task queue and arbitration, robot OPC UA server, robot-lite, onboarding, robot view | Storyline A passes; I-10, I-11, I-13 and I-16 pass |
| v1.0 Agent, correction and control room | 7 Mar 2027 | Document search, tool server, approval queue, impact estimator, production agent, process advisor (feedforward and run-to-run), Ask, Approvals and Corrections views, 3D line, security, benchmark | Storylines C (full), D, E and F pass; I-12, I-14, I-17, I-18 and I-21 to I-24 pass; everything runs from the control room |
| v1.1 ML correction | 28 Mar 2027 | Trained defect model, optimizer inside the PLM process window, shadow mode, retraining and promotion, comparison report | I-25 passes; the comparison with run-to-run control is published |
| Stretch | After v1.1 | Asset Administration Shell via BaSyx; Sparkplug B; an offline mode with a local model; k3s; a mobile robot over [VDA 5050 3.0](https://www.idealworks.com/en/news/vda5050-300-release-march-2026) with Nav2 | One at a time |

Out of scope, on purpose:

- Real PLCs or hardware. Everything is simulated behind real protocols.
- Functional safety. Safety signals are simulated, and the README says so.
- A full MES. MES-lite covers order tracking, genealogy, OEE and ETA only.
- RViz, Gazebo and photorealistic simulation. The control room draws the robot, and the laptop's memory goes to the stack.
- Training models from scratch. Statistics for drift, an API model for the agent, a small local model for embeddings.
- Multiple plants. One site, one line.

## Roadmap

Nine phases over 23 weeks. Each phase is a group of work packages and ends when its checks pass.

*Diagram: roadmap · 9 phases, 5 releases (in the original document).*

| Phase | Dates | Work packages, in order | Ends with |
| --- | --- | --- | --- |
| 0 Foundations | 19–25 Oct | WP-00 to WP-03, then WP-27 | Toolchain installed; core containers healthy; memory measured; contracts written; test kit skeleton running |
| 1 Machines | 26 Oct – 8 Nov | WP-04, WP-05 | Five OPC UA servers browsable in UaExpert |
| 2 Data pipe | 9–29 Nov | WP-06, WP-07, WP-08, WP-28, then WP-09 | v0.1 |
| 3 Enterprise loop | 30 Nov – 13 Dec | WP-10 to WP-12 | v0.2 |
| 4 Robot cell | 14 Dec – 17 Jan | WP-13 to WP-17 | v0.3; five weeks, holidays included |
| 5 Agent and correction | 18 Jan – 7 Feb | WP-18 to WP-21, then WP-25 | Storylines C, D, E and F pass |
| 6 Control room v2 | 8–21 Feb | WP-22 | Every storyline runs from the control room |
| 7 Harden and ship | 22 Feb – 7 Mar | WP-23, WP-24 | v1.0 |
| 8 ML correction | 8–28 Mar | WP-26 | v1.1 |

## Work packages

Each work package is one Claude Code session: a goal, the actions in order, and the checks that prove it is done. Follow the order of the phase table; numbers are stable IDs, so packages added later get new numbers rather than renumbering the rest. A package's checks must pass before the next one starts. "Verify" names the interactions from the functional analysis that the package's tests must cover, and those tests run with the package's layer isolated (`make test-layer LAYER=<name>`), against fakes and recorded traffic from the test kit, never only through the full stack.

### WP-00 · Workstation setup (phase 0)

Goal: a Windows laptop that can build and run every container.

- ☑ Update Windows 11 and the NVIDIA driver
- ☑ In an administrator PowerShell, run `wsl --install` to get WSL2 with Ubuntu, then restart; Ubuntu user `adrianocl`
- ☑ Create `%UserProfile%\.wslconfig` with memory=10GB, processors=8 and swap=8GB; run `wsl --shutdown` to apply it
- ☑ Install Docker Desktop, enable the WSL2 backend and WSL integration for Ubuntu; add the Ubuntu user to the docker group; check with `docker run hello-world` from Ubuntu
- ☑ In Ubuntu: `sudo apt install git make build-essential`; set your Git name and email, `init.defaultBranch main` and `core.autocrlf input`; add an SSH key to GitHub
- ☑ In Ubuntu: install uv (Python package and version manager), then Python 3.12 through uv
- ☑ In Ubuntu: install Node.js LTS through nvm
- ☑ On Windows: install VS Code with the WSL, Dev Containers, Python, Docker and ESLint extensions; open projects from Ubuntu with `code .`
- ☐ In Ubuntu: install Claude Code with the native installer and log in with `claude`
- ☑ On Windows: install UaExpert (free OPC UA client from Unified Automation, registration required) and MQTT Explorer
- ☑ On Windows: install Ollama, pull `nomic-embed-text`, and check it answers on port 11434 and runs on the GPU (`ollama ps` shows 100% GPU)
- ☐ Get an API key for the agent's model provider, with a monthly spend limit; it will live in `.env`, never in Git. Deferred to phase 5 (WP-19)

Verify: `docker run hello-world`, `uv --version`, `node --version`, `claude --version` and `ollama list` all succeed.

#### Setup notes

What went wrong during setup, and the fix, for anyone repeating it:

- **`Wsl/Service/E_UNEXPECTED` when creating the Ubuntu user.** Restart Windows and run `wsl --update`. If it persists, create the user as root: `wsl -d Ubuntu -u root`, then `adduser <name>`, `usermod -aG sudo <name>` and `printf '[user]\ndefault=<name>\n' >> /etc/wsl.conf`, then `wsl --shutdown`.
- **Writing `.wslconfig`.** Use PowerShell rather than Notepad, which may add `.txt`:
  `Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nmemory=10GB`nprocessors=8`nswap=8GB" -Encoding ascii`
- **`permission denied ... /var/run/docker.sock`.** The user is not in the docker group: `sudo usermod -aG docker $USER`. `newgrp` is not installed on this Ubuntu; start a new login shell with `exec su -l $USER` instead, or restart WSL.
- **Line endings.** `git config --global core.autocrlf input` keeps shell scripts in LF, so container entrypoints do not fail with CRLF.
- **nvm.** Install it with the script from its README (v0.40.7 at setup time), then `source ~/.bashrc`. Do not install Ubuntu's `nodejs` package.
- **GPU.** Ollama uses the RTX 3050 through CUDA; the first embedding call takes a few seconds to load the model, later calls take milliseconds.

### WP-01 · Repo and conventions (phase 0)

Goal: an empty but complete monorepo that Claude Code can work in.

- ☑ Create the GitHub repo `pulp` (Apache-2.0) and clone it to `~/pulp` inside Ubuntu
- ☑ Create the folder layout from "Repo and conventions"
- ☑ Python workspace with uv: one package per service, plus a shared common package for schemas, topic helpers, trace IDs and logging
- ☑ Tooling: ruff, mypy, pytest, pre-commit; a Makefile with up, down, test, lint, logs and storyline-<letter>
- ☑ CLAUDE.md at the root: what the project is, a pointer to docs/spec.md, the commands, the conventions, and "never change contracts/ without asking"
- ☑ Put this document in docs/spec.md; create docs/adr/ with ADR-001 (UNS vs point-to-point)
- ☑ .env.example with every variable; .gitignore excludes .env
- ☑ GitHub Actions: lint and unit tests on every push

Verify: CI is green on the empty test suite; make lint passes.

### WP-02 · Core containers and memory budget (phase 0)

Goal: the infrastructure runs, and its real memory use is known.

- ☐ deploy/compose.yaml with the profiles core, enterprise, robot, robot-lite and ai
- ☐ Mosquitto with a TCP listener on 1883 and a WebSocket listener on 9001; users from a password file
- ☐ TimescaleDB with the pgvector extension; init scripts mounted from historian/migrations
- ☐ Grafana with its TimescaleDB data source provisioned
- ☐ Health checks on every service; `make up PROFILES=core` waits for healthy
- ☐ Start the OdooPLM slim image and a ROS 2 Lyrical image once, only to measure; record docker stats figures in the runtime environment table
- ☐ Write ADR-002: robot or robot-lite as the default, based on the measurements

Verify: all core services healthy; measured memory recorded in this document.

### WP-03 · Contracts (phase 0)

Goal: every interface is defined before code depends on it.

- ☐ contracts/assets.yaml: the ISA-95 tree (enterprise pulp, site paris, area molding, line line1, its cells and stations)
- ☐ contracts/topics.md: the UNS scheme, `pulp/paris/molding/line1/<asset>/<class>/<name>` with classes telemetry, state, event, cmd and cmd_result, plus `pulp/_sys/trace` for trace hops
- ☐ JSON Schemas for telemetry, state, event, command, command result and trace hop messages; every message carries trace_id, ts and asset
- ☐ Event types from "Event journal" in one source file, generated for Python and TypeScript
- ☐ SQL migrations: the historian hypertable and journal_events with the listed fields; indexes on ts, asset, order_id and serial
- ☐ Contract tests: valid samples pass, broken samples fail

Verify: make test runs the contract tests; ADR-003 (JSON with schemas vs Sparkplug B) written.

### WP-27 · Test kit: fakes, record and replay, invariants (phase 0, extended in every phase)

Goal: every layer can be tested alone from its first day.

- ☐ testkit/ package with pytest fixtures that start and stop single containers for layer tests
- ☐ `pulp-record` and `pulp-replay`: capture UNS traffic to JSON Lines files and play it back at real or accelerated speed, preserving order and trace IDs
- ☐ Fake OPC UA server driven by a YAML script (values, states, method results, delays, disconnects)
- ☐ Fake UNS publisher and consumer for services that sit between the UNS and an external system
- ☐ Invariant query library: one SQL check per interaction, starting with I-02 to I-04; each later package adds its own
- ☐ Golden dataset format: a journal snapshot plus its expected check results
- ☐ `make test-layer LAYER=<name>` running one layer's tests with its fakes
- ☐ Extended later: fake press 2 (WP-15), fake approval queue (WP-19, WP-25), recorded tool results (WP-21)

Verify: the fake OPC UA server can be browsed in UaExpert; a recorded file replays identically twice; invariant queries pass on a hand-made valid journal and fail on a hand-broken one.

### WP-04 · Simulation core and process models (phase 1)

Goal: a deterministic, causal process that produces parts.

- ☐ Simulation clock (real time or accelerated), seeded random generator, scenario runner reading YAML files from scenarios/
- ☐ Mixer: batches with rotor speed, ram pressure, temperature, mixing energy, dump temperature; a cooling-efficiency parameter for the drift fault
- ☐ Extruder: preform weight with scatter
- ☐ Presses: platen temperature, cure time from the recipe, a simple cure-state model; underfill and porosity probabilities depend on cure state and the compound batch's temperature
- ☐ Vision: pass or fail and defect class from the part's history
- ☐ Part objects carry serial, batch, order and revision through the stations
- ☐ A PackML-style state machine per station (Idle, Starting, Execute, Held, Aborted, Complete)
- ☐ Unit tests: same seed gives the same output; hotter batches raise the underfill rate

Verify: a one-hour accelerated run produces plausible counts, exported to CSV for inspection.

### WP-05 · Station OPC UA servers and fault injection (phase 1)

Goal: each station is a real OPC UA server, like separate machines on a brownfield site.

- ☐ One asyncua server per station, each in its own container, ports 4840 to 4844
- ☐ Address space per station: Identification, State, ProcessValues, Counters, Alarms; methods StartBatch, LoadRecipe and Reset
- ☐ Press 2 interlock variables: CycleDone, MoldOpen, RequestEntry, EntryGranted, RobotClear, CycleStart
- ☐ Fault-injection CLI, for example `pulp-fault mixer cooling_loss --rate 0.5`, through an admin method on each server
- ☐ Basic256Sha256 sign-and-encrypt available but off by default until WP-23

Verify: UaExpert browses all five servers; methods run; an injected fault shows in the values.

### WP-06 · Edge gateway (phase 2)

Goal: the only bridge between the machines and the UNS, and it never loses data.

- ☐ Reads contracts/assets.yaml; connects to every station server; subscribes with a sampling interval and deadband per tag (no polling)
- ☐ Normalizes units, attaches a trace ID, publishes telemetry, state and event messages (I-01, I-03, I-04)
- ☐ Listens on cmd topics, calls the matching OPC UA method, publishes cmd_result (I-05)
- ☐ Store-and-forward: buffers in SQLite while the broker is unreachable, replays in order, emits gateway_buffering and gateway_replayed (I-20)
- ☐ Publishes a trace_hop for each traced message it handles (I-19)
- ☐ Reconnects with backoff on both sides; exposes Prometheus metrics

Verify: I-01 latency test; I-20 test that stops the broker (60 s in CI, 10 minutes manually).

### WP-07 · Historian and journal writers (phase 2)

Goal: every value and every event is stored and queryable.

- ☐ Telemetry writer: batched inserts into the hypertable; a 1-minute continuous aggregate; 30-day retention on raw data
- ☐ Journal writer: consumes every event topic, validates against the schema, writes journal_events; invalid messages go to a dead-letter topic
- ☐ Hourly and per-shift plain-text summaries generated from the journal
- ☐ SQL views for common questions: production by hour, alarms by asset, parts by order
- ☐ Both writers publish trace_hop (I-19)

Verify: I-02 count test; I-03 ordering test; I-04 pairing test.

### WP-08 · Drift detection (phase 2)

Goal: catch the mixer drift before it shows up as scrap.

- ☐ Service subscribed to mixer batch temperature; EWMA and CUSUM with parameters in config
- ☐ Publishes anomaly_detected with the evidence window; clears when the process is back in control

Verify: I-15 in storyline C; no alarm during a two-hour healthy run.

### WP-28 · Watchdog and health panel (phase 2)

Goal: see at any moment whether the running system still behaves as specified.

- ☐ Watchdog service running the invariant queries every N seconds over a sliding window of the live journal
- ☐ Publishes one result per interaction to `pulp/_sys/health`, with the failing events when red
- ☐ Heartbeat convention: every service publishes a heartbeat; the watchdog flags silent ones
- ☐ Per-hop latency computed from trace_hop messages
- ☐ Control room: Health view with checks, heartbeats and latency per hop

Verify: a broken journal fed through the replay tool turns the right checks red; stopping a service flags its heartbeat within the configured time.

### WP-09 · Control room v1 (phase 2)

Goal: see the line and the data flow live in the browser.

- ☐ React + TypeScript app built with Vite in ui/, served by a container; MQTT over WebSockets with mqtt.js
- ☐ Line view in 2D SVG: stations and robot, state colors, counters, active alarms
- ☐ Data flow view: the architecture drawing with message dots moving along each hop; click a message to see its payload and per-hop timestamps by trace ID (I-19)
- ☐ Scenarios panel: start storylines and inject faults through a small scenario API
- ☐ Grafana dashboards: line overview, station detail, events
- ☐ Tag **v0.1**

Verify: storyline C's drift is visible in both views; I-19 checked by hand and written up.

### WP-10 · Odoo and OdooPLM setup and seed data (phase 3)

Goal: a real ERP and PLM holding the line's products, revisions and orders.

- ☐ Add the OdooPLM slim image to the enterprise profile with its own PostgreSQL and a persistent volume
- ☐ Seed script over Odoo's API: compound and part products, BOMs, routing, one work center per station
- ☐ In OdooPLM: part SEAL-12 rev B released, rev C in draft for storyline B, procedures as PDF documents
- ☐ Recipe parameters per revision as a structured JSON attachment, so no custom Odoo module is needed (ADR-004)
- ☐ Order generator: a script creating manufacturing orders for a simulated week

Verify: make seed rebuilds Odoo from empty in one command; the records show in the Odoo UI.

### WP-11 · Integration service (phase 3)

Goal: orders and recipes flow down; confirmations flow up, exactly once.

- ☐ Polls Odoo for released manufacturing orders; resolves the part revision and its recipe from OdooPLM
- ☐ Publishes order_released and a LoadRecipe command to the target station (I-05); refuses an order whose revision is not released (I-09)
- ☐ Consumes part_produced and part_inspected; confirms good and scrap quantities to Odoo with an idempotency key per batch (I-08)
- ☐ Writes the new expected finish to the Odoo order when order_eta_changed arrives (I-14)

Verify: I-05; I-08 with forced duplicate sends; I-09; storyline B end to end.

### WP-12 · MES-lite and OEE (phase 3)

Goal: know what runs where, what each part went through, and why output is lost.

- ☐ Order tracking: which order runs on which station, quantity done, progress
- ☐ Genealogy per serial (I-06, I-07)
- ☐ OEE per station and shift (availability, performance, quality), with downtime reason codes including robot_reassigned, starved and blocked
- ☐ Expected finish per order from the current rate; publishes order_eta_changed when it moves more than a threshold
- ☐ Control room: orders and revisions view
- ☐ Tag **v0.2**

Verify: I-06 and I-07 completeness test; OEE recomputed from the raw journal matches.

### WP-13 · ROS 2 container and robot model (phase 4)

Goal: a headless six-axis arm in a modeled cell, with its motion visible in the UNS.

- ☐ Dockerfile from the official ROS 2 Lyrical image (Ubuntu 26.04) with MoveIt 2 and ros2_control; built and run in the robot profile
- ☐ URDF/xacro of a six-axis arm from an open robot description package, plus the cell: press 2 opening, conveyor, audit table, gripper rack
- ☐ MoveIt configuration with mock hardware; named poses; collision objects for the cell
- ☐ Headless launch file; a bridge node publishing rate-limited joint states and the robot description to the UNS for the control room

Verify: a planned motion runs on mock hardware; joint states appear in MQTT Explorer.

### WP-14 · Robot skills and behavior tree (phase 4)

Goal: the robot programmed as reusable skills, sequenced by a behavior tree.

- ☐ Skills as ROS 2 action servers: unload_press, place_on_conveyor, move_part_to_audit, clear_jam, change_gripper, go_home
- ☐ A simulated gripper with a grip-miss probability, for fault injection
- ☐ Behavior tree (py_trees or BehaviorTree.CPP) for the production cycle; one sub-tree per extra task; a safety stop pre-empts any branch
- ☐ Each skill emits robot_task_started, robot_task_finished or robot_task_failed with its duration (I-11)
- ☐ Record skill and cycle durations to a file, for robot-lite and the impact estimator

Verify: a test per skill on mock hardware; skill durations add up to the cycle time (I-11).

### WP-15 · Cell controller: handshake, task queue, arbitration (phase 4)

Goal: the robot shares its time between press 2 and extra tasks, following the arbitration rules.

- ☐ Interlock state machine with press 2 over OPC UA, a timeout per step, a handshake_step event per step, an alarm on timeout (I-10)
- ☐ Task queue with the four priorities and the five arbitration rules from "Robot tasks and arbitration" (I-13)
- ☐ Accepts approved task commands from the UNS, refuses unapproved ones, publishes the full task lifecycle (I-12)
- ☐ Publishes press_blocked and press_unblocked with reason robot_reassigned (I-14)
- ☐ Robot OPC UA server modeled on OPC 40010-1: identification, state, task control, counters

Verify: I-10 sequence tests including every timeout; I-13 safe-point test; I-12 test that an unapproved command is refused.

### WP-16 · robot-lite stand-in (phase 4)

Goal: a light robot with the same contract, for when memory is short.

- ☐ Python service exposing the same OPC UA server, UNS topics and task lifecycle as the real cell
- ☐ Skill and cycle durations loaded from the WP-14 recordings; synthetic joint states for the control room's 3D view
- ☐ One contract test suite run against both robot and robot-lite

Verify: the same contract tests pass for both implementations.

### WP-17 · Onboarding service (phase 4)

Goal: a new cell is commissioned and scored automatically.

- ☐ Cell self-description as a JSON manifest: identity, capabilities, skills, interfaces, safety signals
- ☐ On cell_registered: map the cell into the asset tree and topics, then run the checks: communication, handshake round trip, cycle time vs takt, safety signals present, gripper test
- ☐ Publish the readiness score and punch list
- ☐ Control room: robot and onboarding view (mode, current task, queue, handshake step, readiness)
- ☐ Tag **v0.3**

Verify: I-16, each of the three injected faults fails its check; storyline A passes.

### WP-18 · Document corpus and search (phase 5)

Goal: the text side of the agent's knowledge, searchable locally.

- ☐ Write 15 to 25 short, realistic documents: procedures, maintenance logs, nonconformance reports, operator notes; store the engineering documents in OdooPLM
- ☐ Indexer: chunk, embed with `nomic-embed-text` through Ollama, store in pgvector with metadata (asset, part, revision, date)
- ☐ Check that containers reach Ollama at host.docker.internal:11434
- ☐ Re-index the hourly and shift summaries from WP-07 on a schedule
- ☐ Retrieval test set: 20 queries, each with its expected document

Verify: retrieval hit rate recorded against the target set in ADR-005; if it misses, try a larger embedding model (the 6 GB GPU has room).

### WP-19 · Tool server and approval queue (phase 5)

Goal: every tool from "Production agent", typed, logged and safe.

- ☐ MCP server exposing the tools with typed inputs and outputs; reads go through a read-only database role
- ☐ Add OdooPLM's own MCP tools for PLM questions
- ☐ Approval queue service: pending actions, approve, schedule or reject, audit log; each approved action executes exactly once through an idempotency key (I-18)
- ☐ Every tool call emits tool_called with its inputs and a hash of its result (I-17)

Verify: tool tests on a seeded database; a rejected action changes nothing (I-18).

### WP-20 · Impact estimator (phase 5)

Goal: know what an extra robot task will cost before approving it.

- ☐ Inputs: press 2 cycle time, spare time per cycle, task duration from the WP-14 recordings, current order quantity and rate, upcoming changeovers
- ☐ Outputs for "now" and "next window": blocked cycles, lost parts, new expected finish
- ☐ Compare predicted against measured loss after each run, from the journal (I-14)

Verify: across ten runs of storyline E, predicted and measured loss agree within one press cycle.

### WP-21 · Production agent, Ask and Approvals views, evaluation (phase 5)

Goal: ask the factory anything, and approve what the agent proposes.

- ☐ Agent loop calling the API model with the tools; a system prompt holding the answer rules; relative times resolved to explicit windows
- ☐ Ask view: the question, the tool calls made, the answer with clickable sources
- ☐ Approvals view: pending actions with their impact estimates; approve now, schedule, or reject
- ☐ Evaluation harness: 30 questions with expected facts, run with make eval; pass rate stored per commit

Verify: storylines C, D and E pass; I-12, I-17 and I-18.

### WP-25 · Process advisor: feedforward and run-to-run (phase 5)

Goal: detected drift becomes bounded, approved and verified recipe corrections.

- ☐ Add a process window per revision (minimum, nominal, maximum for each setting) to the OdooPLM recipe attachment; extend the WP-10 seed; write ADR-006
- ☐ Feedforward rule: batch temperature deviation gives a cure time offset for the parts made from that batch; gain in config
- ☐ Run-to-run EWMA controller on underfill rate per press, with a dead band, a maximum step, one parameter at a time and one change per N batches
- ☐ Window check: inside the window, publish correction_proposed to the approval queue with the predicted effect; outside, publish process_window_exceeded, draft a change order in OdooPLM and request a maintenance work order (I-21, I-22)
- ☐ On approval, send LoadRecipe at the next batch boundary and publish correction_applied; genealogy records the values each part received (I-23)
- ☐ After N parts, compare predicted and measured scrap; keep the correction or roll it back automatically (I-24)
- ☐ Control room: Corrections view

Verify: storyline F passes; I-21 to I-24; a run with a deliberately wrong gain shows the rollback.

### WP-22 · Control room v2 (phase 6)

Goal: the whole line, in 3D, understandable without reading logs.

- ☐ 3D line with React Three Fiber; the arm loaded with urdf-loader and driven by live joint states
- ☐ Robot panel with mode, task and queue; press 2 blocked indicator; an OEE strip with reason codes
- ☐ Layout and performance pass: smooth at 1 Hz telemetry from every station

Verify: each storyline runs and can be followed from the control room alone.

### WP-23 · Security, fault and load tests (phase 7)

Goal: the stack is segmented, authenticated, and its limits are measured.

- ☐ OPC UA sign-and-encrypt with certificates for the gateway and the cell controller
- ☐ Mosquitto users and topic ACLs per service; the browser gets a read-only user and a scenario user
- ☐ One Docker network per Purdue zone; only the gateway, and the cell controller for the interlock, span field and plant
- ☐ Fault tests: kill and restart the broker, the gateway, Odoo and the robot container mid-storyline; add latency and packet loss between zones with a network fault proxy such as Toxiproxy; every check must recover without manual action
- ☐ Soak test: an 8-hour shift at accelerated time with all profiles; RAM stays flat and every check stays green
- ☐ Load benchmark: scale to 5,000 tags at 1 Hz; record latency (p50, p95), CPU, RAM and disk per day in docs/benchmark.md
- ☐ Run the architecture scenarios from "Verification" and record each result

Verify: services refuse wrong credentials; benchmark numbers published.

### WP-24 · Observability, docs and release (phase 7)

Goal: anyone can run it on Windows from the README.

- ☐ Prometheus scraping the gateway and services; a Grafana ops dashboard
- ☐ README: what it is, a GIF of the control room, a Windows quick start (with the WP-00 setup notes), the storylines; architecture page; ADR index
- ☐ Run every interaction check and every storyline; tag **v1.0**

Verify: a clean Windows machine reaches a running line by following the README.

### WP-26 · ML process correction (phase 8)

Goal: learn when a trained model beats the simple controller, and when it does not.

- ☐ Generate training data: simulated runs with deliberately varied settings and drifts (a small design of experiments), labeled from the journal
- ☐ Features per part: batch temperature, mixing energy, preform weight, cure time, platen temperature, press; target: defect or not, and defect class
- ☐ Train a gradient-boosting model (scikit-learn or LightGBM); validate on held-out runs, including probability calibration
- ☐ Optimizer (SciPy) searching inside the PLM process window for the settings that minimize predicted scrap plus a cycle-time penalty
- ☐ Shadow mode: the model proposes next to the run-to-run controller without acting; log both proposals and their predicted outcomes
- ☐ Retraining job and promotion rule; model_trained and model_promoted events (I-25)
- ☐ Write-up in docs/ comparing feedforward plus run-to-run against the ML advisor on storyline F: scrap, cycle time, number of corrections, failures
- ☐ Tag **v1.1**

Verify: I-25; the comparison report is published.

## Repo and conventions

One monorepo whose layout mirrors the architecture.

```
pulp/
├── CLAUDE.md      instructions for Claude Code
├── contracts/     asset tree, topic scheme, JSON Schemas, event types
├── docs/          spec.md (this document), adr/, benchmark.md, notes/
├── common/        shared Python package: schemas, topics, trace IDs, logging
├── testkit/       fakes, record and replay, invariant queries, golden datasets
├── sim/           process models and one OPC UA server per station
├── edge/          edge gateway
├── historian/     migrations, telemetry and journal writers, summaries
├── mes_lite/      order tracking, genealogy, OEE, ETA
├── analytics/     drift detection, process advisor, watchdog
├── integration/   Odoo <-> UNS service
├── robot/         ROS 2 workspace: description, MoveIt config, skills, behavior tree, cell controller
├── robot_lite/    stand-in with the same contract
├── onboarding/    self-description, checks, readiness
├── ai/            corpus, indexer, tool server, approval queue, impact estimator, agent, evals, ML correction
├── ui/            control room (React, TypeScript)
├── scenarios/     storylines A to F, fault definitions
└── deploy/        compose.yaml with profiles, Mosquitto and Grafana config
```

Conventions:

- **Naming.** "PULP" in prose and the README; lowercase `pulp` in code, package names, topics, container names and the repo. CLI tools are prefixed `pulp-`.
- **Contracts first.** Code depends on contracts/; changing a contract needs an ADR.
- **Every message and event carries `trace_id`, `ts` and `asset`.** The simulation clock is the only time source.
- **Tests by layer (see Verification):** unit tests; contract tests, shared by robot and robot-lite; one integration test per storyline, runnable headless with `make storyline-<letter>`.
- **Tooling:** Python 3.12 with uv, ruff, mypy and pytest; TypeScript with Vite; ROS 2 code builds only inside its container.
- **Configuration** through environment variables and .env; secrets are never committed.
- **Git:** conventional commits; one branch and pull request per work package; release tags v0.1, v0.2, v0.3, v1.0 and v1.1.
- **Licensing:** Apache-2.0 for this code; Odoo and OdooPLM run as unmodified containers.

## Risks and open decisions

Scope creep and laptop memory are the two risks most likely to stall the build.

| Risk | Early sign | Fallback |
| --- | --- | --- |
| Scope creep | Work starts on a package before the previous one's checks pass | Strict package order; ideas parked under a "later" issue label |
| Laptop memory | docker stats above the 10 GB WSL2 cap, or swapping | robot-lite instead of robot; fewer Odoo workers; start enterprise only for storylines that need it |
| ROS 2 in a container on WSL2 | Build or networking problems | Official Lyrical image; mock hardware; no GUI needed |
| Odoo's data model | A week lost inside Odoo | Seed script over the API; no custom modules; recipes as JSON attachments |
| Agent reliability | Wrong tool chosen, or numbers not in any tool result | Fixed typed tools; answer rules; make eval on every commit |
| API cost | The bill grows during development | Recorded tool results for tests; a cheaper model for development runs; a monthly budget alert |
| Code drifting from the spec | Code contradicts contracts/ or this document | CLAUDE.md rules; contract tests in CI; one package per session; update docs/spec.md with every decision |
| Implausible simulation numbers | Cycle times or scrap rates nobody would believe | Calibrate against real orders of magnitude and write the assumptions in docs/ |
| Corrections make things worse | Settings oscillate, or scrap rises after a correction | Dead band and step limits; approval by default; automatic rollback; the ML model stays in shadow mode until it beats run-to-run |
| Debugging the assembled system | A failure you cannot place in one layer | Follow the trace ID to the last hop that saw the message; replay the recorded traffic into that layer alone and debug it there |

Decide these before Phase 0 ends:

- ☐ Domain: the rubber-part line
- ☐ Language model provider for the agent, and a monthly budget
- ☑ GPU memory and the embedding model: RTX 3050 with 6 GB; `nomic-embed-text` through Ollama, about 320 MB of GPU memory
- ☐ robot or robot-lite as the default, after the WP-02 measurements
- ☐ Weekly hours: under about 10, v1.0 moves to April
- ☑ The project name: PULP

## Sources

- [ROS 2 Lyrical Luth release announcement](https://discourse.openrobotics.org/t/ros-2-lyrical-luth-released/55021), Open Robotics, 22 May 2026
- [OdooPLM repository](https://github.com/OmniaGit/odooplm), OmniaSolutions
- [VDA 5050 3.0.0 release](https://www.idealworks.com/en/news/vda5050-300-release-march-2026), Idealworks
- [asyncua on PyPI](https://pypi.org/project/asyncua/)
- [MoveIt 2 repository](https://github.com/moveit/moveit2)
- [OPC 40010-1 Robotics](https://opcfoundation.org/developer-tools/specifications-opc-ua-information-models/opc-unified-architecture-for-robotics/), OPC Foundation
- [Eclipse BaSyx Go components](https://pkg.go.dev/github.com/eclipse-basyx/basyx-go-components)
- [United Manufacturing Hub relicensing to Apache 2.0](https://www.umh.app/insight/united-manufacturing-hub-relicensed-to-apache-2-0)
- [MORYX framework](https://github.com/phoenixcontact/moryx-framework), Phoenix Contact
- [SINDIT](https://github.com/SINTEF-9012/SINDIT), SINTEF
- [opcua-mcp](https://enterprisedna.co/directories/mcp/kukapay-opcua-mcp) and [machina-ai](https://pypi.org/project/machina-ai/)
