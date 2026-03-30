<p align="center">
  <img src="docs/logo.png" width="200" alt="CC Swarm">
</p>

<h1 align="center">CC Swarm</h1>

<p align="center">
  Multi-agent coordination for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> over tmux
</p>

<p align="center">
  <b>Peer mesh</b> &middot; Pure bash &middot; Zero dependencies beyond tmux + jq<br>
  ~3200 lines &middot; 151 tests &middot; Claude Code plugin
</p>

---

## The Problem

Claude Code's built-in Agent Teams splits the terminal into panes.
At 5+ agents, each pane is unreadably small.
At 10+, it's unusable.

CC Swarm gives every agent a full tmux window.
Dispatch tasks, exchange reviews, merge branches, monitor liveness -- all via a single CLI.
Scale to as many agents as your machine (and API quota) can handle.

## Features

| Category            | What you get                                                                     |
| ------------------- | -------------------------------------------------------------------------------- |
| **Task lifecycle**  | Create, dispatch, track, collect -- structured V2 protocol with envelopes        |
| **Review exchange** | Cross-agent code review with auto-incrementing rounds (r1, r2, r3...)            |
| **Teams**           | Roles (worker/lead/monitor), teams, topology, capabilities                       |
| **Messaging**       | Async mailbox with push notification via tmux paste                              |
| **QA protocol**     | Tracked question-answer exchanges between agents                                 |
| **Heartbeat**       | Hook-driven liveness detection, stale agent alerts                               |
| **Drain signal**    | Graceful shutdown -- agent finishes current task, then stops                      |
| **Dispatch dedup**  | Prevents accidental double-dispatch (`--force` to override)                      |
| **File locking**    | Atomic mkdir-based locks with PID stale detection                                |
| **Activity log**    | Unified JSONL event stream for audit and debugging                               |
| **Merge coord**     | Non-destructive conflict detection via `git merge-tree`, sequential safe merge    |
| **DAG workflows**   | Declare task dependencies in JSON, let swarm schedule execution                   |
| **Monitor agent**   | Dedicated watchdog that detects stuck/idle agents and intervenes                  |
| **Session launch**  | Sequential launch with readiness detection and auto-registration                 |

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
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
                   |-- tasks/           # V2 task dirs (envelope + prompt + result)
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

### V2 Dispatch (Structured)

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

### V1 Dispatch (Quick)

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

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm list [-v]`                          | Show registered agents (`-v` adds session ID)       |
| `swarm status`                             | Dashboard of all agents                             |
| `swarm launch <session> [--count N]`       | Launch CC sessions sequentially in tmux             |
| `swarm register-all`                       | Bulk-register existing CC sessions                  |

### Task Lifecycle

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm task create --id X --from P --to P` | Create a structured task with envelope               |
| `swarm task status <id>`                   | Show task state                                     |
| `swarm task list [--state S]`              | List tasks, optionally filtered                     |
| `swarm dispatch --task <id> [--force]`     | V2 dispatch (target from envelope, dedup-protected) |
| `swarm dispatch <target> "prompt"`         | V1 dispatch (simple, no tracking)                   |
| `swarm dispatch <target> --file <path>`    | V1 dispatch from file                               |
| `swarm monitor <target> --wait <seconds>`  | Block until target finishes                         |
| `swarm collect <target>`                   | Get last assistant response text                    |

### Review

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm review <task_id> --reviewer <pane>` | Request cross-agent review (auto-increments rounds) |

### Communication

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm send <target> "msg"`               | Async message to inbox (with tmux push)             |
| `swarm inbox [--peek]`                     | Read your inbox (`--peek` = don't clear)            |
| `swarm ask <target> "question"`            | Send tracked QA question                            |
| `swarm reply <qa_id> "answer"`             | Reply to a QA question                              |
| `swarm qa [--state S]`                     | List QA records                                     |

### Agent Management

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm card [<target>]`                    | Show agent card                                     |
| `swarm card set-role <target> <role>`      | Set role (worker, lead, monitor)                    |
| `swarm card set-team <target> <team>`      | Assign to team                                      |
| `swarm card set-caps <target> <c1,c2>`     | Set capabilities                                    |
| `swarm heartbeat [--timeout N]`            | Show agent liveness (default: 60s)                  |
| `swarm drain <target>`                     | Signal: stop after current task                     |
| `swarm cancel-drain <target>`              | Cancel a drain signal                               |
| `swarm check-drain --target <pane>`        | Check if agent is draining                          |

### Teams

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm team create <name> --lead <pane>`   | Create a team                                       |
| `swarm team add <name> <p1> [p2 ...]`      | Add members                                         |
| `swarm team remove <name> <pane>`          | Remove member                                       |
| `swarm team show <name>`                   | Show team details                                   |
| `swarm team list`                          | List all teams                                      |
| `swarm team delete <name>`                 | Delete a team                                       |
| `swarm topology`                           | Show full topology                                  |

### Operations

| Command                                    | Description                                         |
| ------------------------------------------ | --------------------------------------------------- |
| `swarm log [--last N]`                     | Show activity log (default: last 50)                |
| `swarm merge --base B [--sources S1,S2]`   | Merge worktree branches (conflict-safe)             |
| `swarm merge --base B --dry-run`           | Check for conflicts without merging                 |
| `swarm monitor-start [--session S]`        | Launch the monitor agent                            |
| `swarm monitor-status`                     | Show monitor report                                 |
| `swarm run <dag.json> [--dry-run]`         | Execute a DAG workflow                              |

## Plugin Structure

```
cc-swarm/
|-- .claude-plugin/
|   +-- plugin.json              # Plugin manifest
|-- scripts/
|   |-- swarm                    # Main CLI (2631 lines, bash)
|   |-- swarm_lock.sh            # Shared lock library (52 lines)
|   +-- swarm_dag.py             # DAG workflow engine (531 lines)
|-- hooks/
|   |-- hooks.json               # SessionStart, UserPromptSubmit, Stop
|   +-- register-agent.sh        # Auto-registration + heartbeat (115 lines)
|-- skills/
|   +-- swarm/
|       +-- SKILL.md             # Teaches Claude the swarm protocol (353 lines)
|-- agents/
|   +-- monitor.md               # Monitor agent prompt template
|-- tests/
|   |-- test_merge.bats          # Merge coordinator
|   |-- test_phase1.bats         # Agent cards, task lifecycle
|   |-- test_phase2.bats         # V2 dispatch, dedup
|   |-- test_phase3.bats         # Team CRUD, topology
|   |-- test_phase4.bats         # Review exchange protocol
|   |-- test_phase5.bats         # Monitor agent template + commands
|   |-- test_phase6.bats         # Mailbox, QA protocol
|   |-- test_phase7.bats         # Heartbeat, dedup, drain signal
|   |-- test_phase8.bats         # File locking, activity log
|   +-- test_structure.bats      # Repo structure validation
+-- docs/
    +-- logo.png
```

## Testing

```bash
bats tests/                      # Full suite: 151 tests
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

**~3200 lines of bash.**
No npm.
No TypeScript runtime.
No Docker.
Dependencies: bash, tmux, jq.
That's it.

## License

MIT
