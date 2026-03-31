<p align="center">
  <img src="docs/banner.png" alt="CC Swarm">
</p>

<h1 align="center">CC Swarm</h1>

<p align="center">
  Peer-mesh multi-agent coordination for <a href="https://github.com/anthropics/claude-code">Claude Code</a> over tmux
</p>

<p align="center">
  Pure bash &middot; Zero dependencies beyond tmux + jq &middot; Claude Code plugin<br>
  ~3,200 lines &middot; 190 tests &middot; 40+ CLI commands
</p>

---

## Why CC Swarm?

Claude Code's built-in [Agent Teams](https://docs.anthropic.com/en/docs/claude-code/agent-teams) spawns teammates as subprocesses.
At 5+ agents, visibility degrades.
At 10+, debugging becomes guesswork.

CC Swarm takes a different approach: **every agent is an independent Claude Code session in its own tmux window**.
Full context window per agent.
Full scrollback.
Full autonomy.

Dispatch tasks, exchange binding reviews, merge branches, monitor liveness -- all through a single CLI that reads and writes plain JSON files.
Scale to as many agents as your machine (and API quota) can handle.

## Comparison

The Claude Code multi-agent ecosystem is growing fast.
Here is where CC Swarm fits relative to the major alternatives.

| | **CC Swarm** | **[OMC](https://github.com/Yeachan-Heo/oh-my-claudecode)** | **[Claude Squad](https://github.com/smtg-ai/claude-squad)** | **[Gas Town](https://github.com/steveyegge/gastown)** | **[Overstory](https://github.com/jayminwest/overstory)** | **Agent Teams** (built-in) |
| --- | --- | --- | --- | --- | --- | --- |
| **Stars** | 1 | 17.7k | 6.7k | 13.3k | 1.1k | -- (built-in) |
| **Language** | Bash | TypeScript | Go | Go | TypeScript | TypeScript |
| **LOC** | ~3,200 | ~182k TS | ~6k | ~12k+ | ~8k | -- (part of CC) |
| **Architecture** | Peer mesh | Hub-spoke | Session manager | Worktree manager | Worktree orchestrator | File-based teams |
| **Agent isolation** | tmux windows | tmux panes / worktrees | tmux sessions + worktrees | tmux + worktrees | tmux + worktrees | Subprocesses |
| **Communication** | Mailbox + structured tasks | File-based JSONL mailbox | None (manual) | Shared planning files | SQLite mail | File append/read |
| **Review protocol** | Binding verdicts (ACCEPT/REVISE/REJECT), auto-incrementing rounds | Agent role (no gate) | None | None | None | None |
| **Task lifecycle** | Create, dispatch, track, update, collect | Pipeline stages | None (session-level) | None (session-level) | Task queue | Shared task list |
| **Merge coordinator** | `git merge-tree` conflict detection + sequential merge | `git merge-tree` + `--no-ff` | None | Manual | Tiered conflict resolution | None |
| **DAG workflows** | JSON dependency graph + scheduler | Pipeline stages | None | None | None | Dependency tracking |
| **Monitor agent** | Dedicated watchdog (stuck detection, auto-nudge, escalation) | HUD status bar | Status display | TUI status | None | None |
| **Drain / graceful shutdown** | Yes | Yes (`omc wait`) | None | None | None | None |
| **Multi-runtime** | Claude Code only | Claude + Codex + Gemini | Claude + Codex + OpenCode + Amp | Claude Code only | 11 runtimes | Claude Code only |
| **Dependencies** | bash, tmux, jq | Node.js 20+, tmux | Go binary | Go binary | Node.js, tmux | None (built-in) |
| **Install** | `git clone` + symlink | `npm i -g` | Binary download | Binary download | `npm i -g` | Enable in settings |

### Broader ecosystem

Beyond Claude Code-specific tools, CC Swarm's design draws from and contrasts with general multi-agent orchestration:

| | **CC Swarm** | **[ClawTeam](https://github.com/HKUDS/ClawTeam)** (HKUDS) | **[Google A2A](https://github.com/a2aproject/A2A)** | **[AI Scientist v2](https://github.com/SakanaAI/AI-Scientist-v2)** |
| --- | --- | --- | --- | --- |
| **Stars** | 1 | 4.1k | 22.9k | 4.1k |
| **Type** | CLI tool | Python framework | Protocol spec | Research system |
| **Language** | Bash (~3.2k LOC) | Python (~21k LOC) | Spec + SDKs | Python (~13k LOC) |
| **Architecture** | Peer mesh, filesystem | Swarm, ZeroMQ + file transport | JSON-RPC / gRPC | Tree search + manager |
| **Agent backends** | Claude Code | Claude Code, Codex, Cursor, nanobot, any CLI | Any (protocol-level) | Anthropic, OpenAI (API) |
| **Communication** | Mailbox + tasks | Mailbox + routing policies | Message + Task protocol | Shared journal tree |
| **Coordination** | File locks + hooks | Task store + locking | Agent Cards + Tasks | Manager agent + BFTS |
| **Domain** | General dev | General dev | Cross-framework interop | ML research |
| **Dashboard** | CLI only | Web dashboard | N/A | N/A |

**ClawTeam** (HKU Data Science Lab) is the closest architectural peer -- it has mailbox routing, task management with locking, and multi-backend support.
The key difference is scope: ClawTeam is a Python framework (~21k LOC) with ZeroMQ transport and a web dashboard; CC Swarm is a bash CLI (~3.2k LOC) that uses the filesystem as its only transport.

**Google A2A** is a protocol specification, not an implementation.
It defines how opaque agents discover each other (Agent Cards) and exchange tasks (JSON-RPC).
CC Swarm's envelope-based task protocol (envelope.json + prompt.md + status.json) is conceptually similar to A2A's Task model, though CC Swarm's is filesystem-native rather than network-native.

**AI Scientist v2** (Sakana AI) is domain-specific (ML research automation) rather than general multi-agent coordination.
Its progressive agentic tree search (BFTS) is a different paradigm from CC Swarm's dispatch-and-collect model.

### Design trade-offs

**CC Swarm** optimizes for **transparency and debuggability**.
Every piece of state is a JSON file you can `cat`.
Every command is a bash function you can read.
The trade-off is no GUI, no TUI, and Claude-only.

**OMC** optimizes for **zero-config productivity**.
Team plan, PRD generation, smart model routing (Haiku/Sonnet/Opus tiers) that saves 30-50% on tokens.
The trade-off is 182k lines of TypeScript and a hub-spoke architecture where workers cannot talk to each other directly.

**Claude Squad** and **Gas Town** optimize for **session management**.
Launch many agents, monitor their status, switch between them.
They don't provide inter-agent communication, task tracking, or review protocols -- you manage coordination manually.

**Overstory** optimizes for **runtime-agnosticism**.
Its adapter pattern supports 11 different AI CLIs.
The trade-off is less depth in any single runtime's features.

**Agent Teams** (built-in) optimizes for **zero-install simplicity**.
Teammates share a filesystem-based protocol at `~/.claude/`.
The trade-off is experimental status, limited visibility into agent state, and no review gate.

### What CC Swarm does differently

1. **Peer mesh, not hub-spoke.** Any agent can dispatch to any other. No central coordinator bottleneck.
2. **Binding review protocol.** ACCEPT/REVISE/REJECT verdicts with auto-incrementing rounds. Reviews are gates, not suggestions.
3. **Full context per agent.** Each agent is an independent CC session with its own 200k-token context window, not a subagent with a fraction of the parent's context.
4. **Deterministic status detection.** Process tree + plugin hooks = no screen scraping, no TUI heuristics.
5. **Minimal footprint.** ~3,200 lines of bash. No npm, no Docker, no runtime. Dependencies: bash, tmux, jq.

## Features

| Category           | What you get                                                                    |
| ------------------ | ------------------------------------------------------------------------------- |
| **Task lifecycle** | Create, dispatch, track, update, collect -- structured protocol with envelopes  |
| **Review exchange** | Cross-agent code review with binding verdicts and auto-incrementing rounds     |
| **Teams**          | Roles (worker/lead/monitor), teams, topology, capabilities                      |
| **Messaging**      | Async mailbox, push notification, and broadcast to all idle agents              |
| **QA protocol**    | Tracked question-answer exchanges between agents                                |
| **Heartbeat**      | Hook-driven liveness detection, stale agent alerts                              |
| **Drain signal**   | Graceful shutdown -- agent finishes current task, then stops                     |
| **Dispatch dedup** | Prevents accidental double-dispatch (`--force` to override)                     |
| **File locking**   | Atomic mkdir-based locks with PID stale detection                               |
| **Activity log**   | Unified JSONL event stream for audit and debugging                              |
| **Merge coord**    | Non-destructive conflict detection via `git merge-tree`, sequential safe merge   |
| **DAG workflows**  | Declare task dependencies in JSON, let swarm schedule execution                  |
| **Monitor agent**  | Dedicated watchdog that detects stuck/idle agents and intervenes                 |
| **Session launch** | Sequential launch with readiness detection and auto-registration                |
| **Resume-all**     | Batch resume CC sessions from agent cards after restart                          |
| **Triage**         | Parse review results into Linear tickets with severity mapping                  |
| **Atomic rename**  | Update CC session + pane title + window name + agent card in one command         |

## Quick Start

### Prerequisites

- [Claude Code](https://github.com/anthropics/claude-code) CLI
- [tmux](https://github.com/tmux/tmux)
- [jq](https://jqlang.github.io/jq/)
- Python 3.11+ with [uv](https://github.com/astral-sh/uv) (for DAG workflows only)

### Install

```bash
git clone https://github.com/x-zheng16/cc-swarm.git ~/cc-plugins/cc-swarm
ln -s ~/cc-plugins/cc-swarm/scripts/swarm ~/.local/bin/swarm
swarm help
```

### Enable as Claude Code Plugin

Add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "cc-swarm@local": true
  }
}
```

Once enabled, the plugin automatically:
- Registers each CC session via hooks (SessionStart, UserPromptSubmit, Stop)
- Tracks idle/busy status and heartbeat timestamps in real-time
- Makes the `swarm` skill available to all sessions

### First Commands

```bash
# See all registered agents
swarm list -v

# Dispatch a quick task
swarm dispatch dev:worker.0 "Run the test suite and report failures"

# Wait for it
swarm monitor dev:worker.0 --wait 300

# Read the result
swarm collect dev:worker.0
```

## How It Works

```
tmux session "dev"
+---------+---------+---------+---------+---------+
| lead    | worker1 | worker2 | worker3 | monitor |
| (idle)  | (busy)  | (idle)  | (busy)  | (idle)  |
+---------+---------+---------+---------+---------+
     |         |         |         |         |
     +---------+---------+---------+---------+
                         |
                   ~/.claude-swarm/
                   |-- agents/          # JSON card per agent (status, role, heartbeat)
                   |-- tasks/           # Task dirs (envelope + prompt + result)
                   |-- mailbox/         # Per-agent async inboxes
                   |-- qa/              # Tracked QA exchanges
                   |-- drain/           # Drain signal files
                   |-- monitor/         # Monitor agent state
                   |-- topology.json    # Team definitions
                   |-- activity.jsonl   # Unified event log
```

**Peer mesh, not hub-spoke.**
Any agent can talk to any other agent.
Teams are organizational, not communication boundaries.

### Status Detection

```
Process tree (definitive)     Is CC alive? Are tool subprocesses running?
       |
       v
Hook-reported (event-driven)  Hooks fire on SessionStart (idle), PromptSubmit (busy), Stop (idle)
       |
       v
Fallback                      CC alive + no tools + no hook = idle
```

No TUI heuristics.
No screen scraping.
Process tree + hooks = deterministic status.

## Usage

### Structured Dispatch

The full-featured way to delegate work with tracking:

```bash
# 1. Create the task
swarm task create --id 20260330_auth_refactor \
    --from dev:lead.0 --to dev:worker1.0 \
    --type task --prompt "Refactor the auth module to use JWT"

# 2. Dispatch (target read from envelope)
swarm dispatch --task 20260330_auth_refactor

# 3. Wait
swarm monitor dev:worker1.0 --wait 600

# 4. Read result
cat ~/.claude-swarm/tasks/20260330_auth_refactor/result.md
```

### Quick Dispatch

For simple, untracked tasks:

```bash
swarm dispatch dev:worker1.0 "Run the test suite and report failures"
swarm dispatch dev:worker1.0 --file ~/tasks/complex_prompt.md
```

### Cross-Agent Review

Generator-evaluator separation -- never review your own work:

```bash
# Author requests review
swarm review 20260330_auth_refactor --reviewer dev:worker2.0

# Creates 20260330_auth_refactor_review_r1 and dispatches
# If r1 exists, auto-creates r2, r3, etc.
```

Reviews produce structured verdicts: **ACCEPT** (proceed), **REVISE** (must fix all Critical + Important items), or **REJECT** (rethink approach).
The reviewer is a gatekeeper -- verdicts are binding.

### Fan-Out / Fan-In

```bash
# Fan out
swarm dispatch dev:worker1.0 --file task_a.md
swarm dispatch dev:worker2.0 --file task_b.md
swarm dispatch dev:worker3.0 --file task_c.md

# Fan in
swarm monitor dev:worker1.0 --wait 600
swarm monitor dev:worker2.0 --wait 600
swarm monitor dev:worker3.0 --wait 600

A=$(swarm collect dev:worker1.0)
B=$(swarm collect dev:worker2.0)
C=$(swarm collect dev:worker3.0)
```

### Messaging

```bash
# Async mailbox (with tmux push notification)
swarm send dev:worker1.0 "Results ready at /tmp/analysis.json"
swarm broadcast "New feature shipped: swarm task update. Reload skill."
swarm inbox              # read and clear
swarm inbox --peek       # read without clearing

# Tracked QA
swarm ask dev:lead.0 "Should we use streaming or batch API?"
swarm reply qa_20260330_100253_abc "Streaming. See design doc."
swarm qa --state pending
```

### DAG Workflows

Declare task dependencies, let swarm handle scheduling:

```json
{
  "id": "my-pipeline",
  "max_parallel": 3,
  "tasks": {
    "design":    {"target": "dev:1.0", "prompt": "Design the system"},
    "implement": {"target": "dev:2.0", "depends_on": ["design"]},
    "test":      {"target": "dev:3.0", "depends_on": ["design"]},
    "integrate": {"target": "dev:1.0", "depends_on": ["implement", "test"]}
  }
}
```

```bash
swarm run pipeline.json --dry-run   # validate DAG
swarm run pipeline.json             # execute
swarm run pipeline.json --resume    # resume after interruption
```

### Merge Coordinator

After agents finish work in git worktrees, merge branches back safely:

```bash
# Dry run -- detect conflicts without merging
swarm merge --base main --dry-run

# Output:
#   [CLEAN]    feature-auth     (3 files changed)
#   [CLEAN]    feature-api      (8 files changed)
#   [CONFLICT] feature-ui       2 conflicted file(s)

# Merge only the clean branches
swarm merge --base main --sources feature-auth,feature-api
```

### Operations

```bash
# Heartbeat -- who's alive?
swarm heartbeat --timeout 30

# AGENT                     STATUS   LIVENESS   LAST HEARTBEAT
# dev:lead.0                idle     alive      12s ago
# dev:worker1.0             busy     alive      3s ago
# dev:worker2.0             idle     stale      5m ago

# Drain -- graceful shutdown
swarm drain dev:worker2.0
swarm check-drain --target dev:worker2.0
swarm cancel-drain dev:worker2.0

# Activity log
swarm log --last 20

# Teams
swarm team create backend --lead dev:lead.0
swarm team add backend dev:worker1.0 dev:worker2.0
swarm topology
```

## Command Reference

### Core

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm list [-v]`                        | Show registered agents (`-v` adds session ID)     |
| `swarm status`                           | Dashboard of all agents                           |
| `swarm launch <session> [--count N] [--after W]` | Launch CC sessions (`--after` inserts adjacent) |
| `swarm register-all`                     | Bulk-register existing CC sessions                |
| `swarm resume-all [--dry-run]`           | Batch resume CC sessions from agent cards         |
| `swarm rename <name> [--target <pane>]`  | Atomic rename (CC + pane title + window + card)   |

### Task Lifecycle

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm task create --id X --from P --to P` | Create a structured task with envelope          |
| `swarm task status <id>`                 | Show task state                                   |
| `swarm task update <id> --state <S>`     | Update task state (appends transition)            |
| `swarm task list [--state S]`            | List tasks, optionally filtered                   |
| `swarm dispatch --task <id> [--force]`   | Structured dispatch (target from envelope)        |
| `swarm dispatch <target> "prompt"`       | Quick dispatch (simple, no tracking)              |
| `swarm dispatch <target> --file <path>`  | Quick dispatch from file                          |
| `swarm monitor <target> --wait <seconds>` | Block until target finishes                      |
| `swarm collect <target>`                 | Get last assistant response text                  |

### Review

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm review <task_id> --reviewer <pane>` | Request cross-agent review (auto-increments rounds) |
| `swarm triage <task_id> [--dry-run]`     | Parse review into Linear tickets                  |

### Communication

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm send <target> "msg"`             | Async message to inbox (with tmux push)           |
| `swarm broadcast "msg"`                 | Send message to all idle agents                   |
| `swarm inbox [--peek]`                   | Read your inbox (`--peek` = don't clear)          |
| `swarm ask <target> "question"`          | Send tracked QA question                          |
| `swarm reply <qa_id> "answer"`           | Reply to a QA question                            |
| `swarm qa [--state S]`                   | List QA records                                   |

### Agent Management

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm card [<target>]`                  | Show agent card                                   |
| `swarm card set-role <target> <role>`    | Set role (worker, lead, monitor)                  |
| `swarm card set-team <target> <team>`    | Assign to team                                    |
| `swarm card set-caps <target> <c1,c2>`   | Set capabilities                                  |
| `swarm heartbeat [--timeout N]`          | Show agent liveness (default: 60s)                |
| `swarm drain <target>`                   | Signal: stop after current task                   |
| `swarm cancel-drain <target>`            | Cancel a drain signal                             |
| `swarm check-drain --target <pane>`      | Check if agent is draining                        |

### Teams

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm team create <name> --lead <pane>` | Create a team                                     |
| `swarm team add <name> <p1> [p2 ...]`   | Add members                                       |
| `swarm team remove <name> <pane>`        | Remove member                                     |
| `swarm team show <name>`                 | Show team details                                 |
| `swarm team list`                        | List all teams                                    |
| `swarm team delete <name>`               | Delete a team                                     |
| `swarm topology`                         | Show full topology                                |

### Operations

| Command                                  | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `swarm log [--last N]`                   | Show activity log (default: last 50)              |
| `swarm merge --base B [--sources S1,S2]` | Merge worktree branches (conflict-safe)           |
| `swarm merge --base B --dry-run`         | Check for conflicts without merging               |
| `swarm monitor-start [--session S]`      | Launch the monitor agent                          |
| `swarm monitor-status`                   | Show monitor report                               |
| `swarm run <dag.json> [--dry-run]`       | Execute a DAG workflow                            |

## Plugin Structure

```
cc-swarm/
|-- .claude-plugin/
|   +-- plugin.json              # Plugin manifest
|-- scripts/
|   |-- swarm                    # Main CLI (~3,000 lines, bash)
|   |-- swarm_lock.sh            # Shared lock library (52 lines)
|   +-- swarm_dag.py             # DAG workflow engine (531 lines)
|-- hooks/
|   |-- hooks.json               # SessionStart, UserPromptSubmit, Stop
|   +-- register-agent.sh        # Auto-registration + heartbeat (130 lines)
|-- skills/
|   +-- swarm/
|       +-- SKILL.md             # Teaches Claude the swarm protocol (384 lines)
|-- agents/
|   +-- monitor.md               # Monitor agent prompt template
|-- tests/
|   |-- test_merge.bats          # Merge coordinator (10 tests)
|   |-- test_phase1.bats         # Agent cards, task lifecycle (22 tests)
|   |-- test_phase2.bats         # Dispatch, dedup (11 tests)
|   |-- test_phase3.bats         # Team CRUD, topology (20 tests)
|   |-- test_phase4.bats         # Review exchange protocol (13 tests)
|   |-- test_phase5.bats         # Monitor agent template + commands (12 tests)
|   |-- test_phase6.bats         # Mailbox, QA protocol (15 tests)
|   |-- test_phase7.bats         # Heartbeat, dedup, drain signal (9 tests)
|   |-- test_phase8.bats         # File locking, activity log (8 tests)
|   |-- test_resume_all.bats     # Resume-all (11 tests)
|   |-- test_structure.bats      # Repo structure validation (16 tests)
|   |-- test_task_update.bats    # Task state update (11 tests)
|   +-- test_triage.bats         # Triage command (10 tests)
+-- docs/
    +-- logo.png
```

## Testing

```bash
bats tests/                      # Full suite: 190 tests
bats tests/test_merge.bats       # Run specific test file
```

All tests run without tmux -- they test the CLI logic, JSON handling, state transitions, and protocol correctness using temporary directories.

## Design Philosophy

**Peer mesh, not hub-spoke.**
No central orchestrator.
Every agent is equal; any agent can dispatch to any other.
Teams provide structure, not gatekeeping.

**Stateless CLI, stateful filesystem.**
The `swarm` binary reads/writes `~/.claude-swarm/` and exits.
No daemon, no sidecar, no runtime.
State is plain JSON files -- debuggable with `cat` and `jq`.

**Hooks, not polling.**
Claude Code's plugin hooks fire on SessionStart, PromptSubmit, and Stop.
Each hook writes the agent card with current status and heartbeat.
No cron jobs, no background threads.

**Convention over configuration.**
Task IDs follow `YYYYMMDD_slug`.
Targets are tmux pane addresses (`session:window.pane`).
Results go to `result.md`.
No config files.

**~3,200 lines of bash.**
No npm.
No TypeScript runtime.
No Docker.
Dependencies: bash, tmux, jq.
That's it.

## License

MIT
