---
name: swarm
description: Coordinate with other Claude Code sessions running in tmux windows. Use when you need to delegate tasks to other agents, check their status, or collect their results.
---

# CC Swarm — Multi-Agent Coordination

You can coordinate with other Claude Code sessions running in tmux windows using the `swarm` CLI.
Each CC session is a peer agent.
You can dispatch tasks, monitor progress, and collect results.

## Setup

`swarm` is on PATH (`~/.local/bin/swarm`).
No setup needed — just call it directly.

## Quick Reference

| Command | What it does |
| --- | --- |
| `swarm list` | Show all CC sessions with status |
| `swarm launch <session> [options]` | Launch CC sessions sequentially in tmux |
| `swarm dispatch <target> "prompt"` | Send a prompt to another CC session |
| `swarm dispatch <target> --file <path>` | Send a long prompt from file |
| `swarm monitor <target> --wait 300` | Block until target finishes |
| `swarm collect <target>` | Get last assistant response text |
| `swarm status` | Dashboard of all agents |
| `swarm send <target> "msg"` | Send async message to agent's inbox |
| `swarm inbox` | Read and clear your inbox |
| `swarm inbox --peek` | Read inbox without clearing |
| `swarm run <dag.json>` | Execute a DAG workflow |
| `swarm run <dag.json> --dry-run` | Validate DAG without dispatching |
| `swarm run <dag.json> --resume` | Resume interrupted DAG |

## Launching Sessions

**Critical rule: CC sessions must be launched one at a time.**
The `cc` / `cc2` command runs `_cc_launch()` which does git pulls and CC update checks.
Concurrent launches cause race conditions.
`swarm launch` enforces this by launching sequentially and waiting for each session to be ready before starting the next.

### Readiness detection

A CC session is "ready" when:
1. `pane_current_command` becomes a version number (e.g. `2.1.81`) — CC process is running
2. `get_status` returns `idle` — TUI is rendered with prompt visible (`>` or `─────` border)

Both conditions must be true. `swarm launch` polls every 3 seconds until both are met (default timeout: 180s).

### Launch examples

```bash
# Launch 1 CC session in tmux session "xz"
swarm launch xz

# Launch 3 CC sessions sequentially (waits for each to be ready)
swarm launch xz --count 3

# Use cc2 instead of cc
swarm launch xz --count 2 --cmd cc2

# Specify starting window index
swarm launch xz --window 10 --count 4

# Custom timeout (seconds per session)
swarm launch xz --count 5 --timeout 240
```

### When to use launch vs pre-existing sessions

- **Pre-existing**: for long-running agents that stay open across tasks
- **Launch**: when spinning up fresh agents for a batch of work (e.g., DAG workflow, parallel research)

## Workflow

### 1. Find available agents

```bash
swarm list
```

Output shows pane target (e.g., `cw:3.0`), status (idle/busy), session ID, and working directory.

### 2. Dispatch a task

```bash
swarm dispatch cw:3.0 "Run the test suite for uclaw and report any failures"
```

For long prompts, write to a file first:

```bash
cat > /tmp/task.md << 'EOF'
Your detailed task description here...
EOF
swarm dispatch cw:3.0 --file /tmp/task.md
```

The command checks if the target is idle before sending.
Use `--force` to send to a busy agent.

### 3. Wait for completion

```bash
swarm monitor cw:3.0 --wait 600
```

Polls every 5 seconds until the agent returns to idle (max 600s = 10 min).

### 4. Collect the result

```bash
RESULT=$(swarm collect cw:3.0)
echo "$RESULT"
```

Extracts the last assistant text response from the agent's session JSONL log.

## Common Patterns

### Fan-Out: Parallel tasks

```bash
# Find idle agents
swarm list

# Dispatch to multiple agents
swarm dispatch cw:3.0 "Task A"
swarm dispatch cw:5.0 "Task B"
swarm dispatch xz:4.0 "Task C"

# Wait for all to finish
swarm monitor cw:3.0 --wait 600
swarm monitor cw:5.0 --wait 600
swarm monitor xz:4.0 --wait 600

# Collect results
RESULT_A=$(swarm collect cw:3.0)
RESULT_B=$(swarm collect cw:5.0)
RESULT_C=$(swarm collect xz:4.0)
```

### Pipeline: Sequential handoff

```bash
# Step 1: Agent A generates data
swarm dispatch cw:3.0 "Generate test fixtures and save to /tmp/fixtures.json"
swarm monitor cw:3.0 --wait 300

# Step 2: Agent B processes the data
swarm dispatch cw:5.0 "Read /tmp/fixtures.json and run validation tests"
swarm monitor cw:5.0 --wait 300

RESULT=$(swarm collect cw:5.0)
```

### Supervised: Check before continuing

```bash
swarm dispatch cw:3.0 "Analyze the auth module for security issues"
swarm monitor cw:3.0 --wait 600

# Check what it found before proceeding
ANALYSIS=$(swarm collect cw:3.0)
# Based on analysis, decide next steps
```

## Async Mailbox

For non-blocking communication between agents.
Unlike dispatch (which types into the agent's prompt), send drops a message in the target's inbox for later reading.

### Send a message

```bash
swarm send cw:3.0 "Results are ready at /tmp/analysis.json"
```

### Check your inbox

```bash
swarm inbox            # read and clear
swarm inbox --peek     # read without clearing
```

### Example: Coordinator notifies workers

```bash
# Write shared data
echo "task complete" > /tmp/shared_state.json

# Notify all workers (non-blocking)
swarm send cw:3.0 "Shared state updated, check /tmp/shared_state.json"
swarm send cw:5.0 "Shared state updated, check /tmp/shared_state.json"
```

Workers check their inbox at their own pace via `swarm inbox`.

## DAG Workflow: Declarative Task Orchestration

Instead of manually chaining dispatch/monitor/collect, declare dependencies in a `dag.json` and let swarm handle scheduling.

### dag.json format

```json
{
  "id": "my-workflow",
  "max_parallel": 3,
  "tasks": {
    "design": {
      "target": "xz:1.0",
      "prompt": "Design the auth system architecture"
    },
    "api": {
      "target": "xz:2.0",
      "prompt_file": "~/.cc-swarm/tasks/api/prompt.md",
      "depends_on": ["design"],
      "outputs": ["src/auth/api.py"]
    },
    "frontend": {
      "target": "cw:3.0",
      "prompt": "Build login UI components",
      "depends_on": ["design"]
    },
    "integration": {
      "target": "xz:1.0",
      "prompt": "Write integration tests",
      "depends_on": ["api", "frontend"],
      "join": "and"
    }
  }
}
```

Task fields:
- `target` (required): tmux pane to dispatch to
- `prompt` or `prompt_file` (required): inline text or path to prompt file
- `depends_on` (optional): list of task names that must complete first
- `join` (optional): `"and"` (default: wait for ALL deps) or `"or"` (start when ANY dep completes)
- `outputs` (optional): files that must exist after completion (validates success)

### Run a DAG

```bash
# Validate without dispatching
swarm run workflow.json --dry-run

# Execute
swarm run workflow.json

# Resume after interruption (skips completed tasks)
swarm run workflow.json --resume

# Custom timeout and poll interval
swarm run workflow.json --timeout 7200 --poll-interval 15
```

The executor:
1. Validates the DAG (cycle detection, missing deps)
2. Dispatches tasks with no dependencies first
3. Polls running tasks every 10s
4. Dispatches downstream tasks as dependencies complete
5. Skips tasks whose dependencies failed
6. Saves state to `*_state.json` for resume capability

### Example: Research Pipeline

```json
{
  "id": "paper-survey",
  "max_parallel": 4,
  "tasks": {
    "search_papers": {
      "target": "xz:2.0",
      "prompt_file": "~/.cc-swarm/tasks/search/prompt.md",
      "outputs": ["~/cc_tmp/papers.json"]
    },
    "analyze_methods": {
      "target": "cw:3.0",
      "prompt": "Read ~/cc_tmp/papers.json and analyze methods",
      "depends_on": ["search_papers"]
    },
    "analyze_results": {
      "target": "xz:4.0",
      "prompt": "Read ~/cc_tmp/papers.json and compare results",
      "depends_on": ["search_papers"]
    },
    "write_summary": {
      "target": "xz:2.0",
      "prompt": "Write survey summary combining methods and results analysis",
      "depends_on": ["analyze_methods", "analyze_results"],
      "join": "and"
    }
  }
}
```

## Important Notes

- **Never launch CC sessions concurrently.** Use `swarm launch` which starts them one at a time, waiting for each to be ready. This avoids `_cc_launch` race conditions (git pull, CC update, repatch all conflict when run in parallel).
- **Agents keep their own permissions.** Unlike claude-session-driver, you don't control their permission level.
- **Use files for shared data.** Agents share the filesystem. Write to temp files for data exchange.
- **Status detection is heuristic.** If status shows "unknown", the agent may be at an unusual prompt state.
- **Collect reads the session JSONL.** The agent must be registered (SessionStart hook) for collect to work. If not registered, it falls back to pane capture.

## Targeting

Targets use tmux pane addressing: `session_name:window_index.pane_index`

Examples:
- `cw:3.0` — session "cw", window 3, pane 0
- `xz:1.0` — session "xz", window 1, pane 0

Run `swarm list` to see all valid targets.
