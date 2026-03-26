<p align="center">
  <img src="docs/logo.png" width="200" alt="CC Swarm">
</p>

<h1 align="center">CC Swarm</h1>

<p align="center">
  Multi-agent coordination for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> over tmux.
</p>

## Why

Claude Code's built-in Agent Teams uses split panes.
When you're running 100+ agents, each pane becomes unreadably small.

CC Swarm uses tmux windows instead — each agent gets a full window with complete context space, no matter how many you run.
Dispatch tasks, monitor status, collect results, all via CLI.
Pure bash, ~750 lines.

## Install

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [tmux](https://github.com/tmux/tmux)
- [jq](https://jqlang.github.io/jq/)
- Python 3.11+ with [uv](https://github.com/astral-sh/uv)

### Setup

```bash
# Clone the repo
git clone https://github.com/x-zheng16/cc-swarm.git ~/cc-plugins/cc-swarm

# Symlink the CLI to your PATH
ln -s ~/cc-plugins/cc-swarm/scripts/swarm ~/.local/bin/swarm

# Verify
swarm list
```

### Enable as Claude Code Plugin

Add to your `~/.claude/settings.json` under `enabledPlugins`:

```json
{
  "enabledPlugins": {
    "cc-swarm@your-marketplace": true
  }
}
```

Or register directly as a local plugin by placing the repo under your plugin directory.

Once enabled, the plugin automatically:
- Registers each CC session in the agent registry via hooks
- Tracks idle/busy status in real-time
- Makes the `swarm` skill available to all sessions

## Usage

### List all agents

```bash
swarm list
```

```
PANE         STATUS   SESSION_ID                            CWD
----         ------   ----------                            ---
dev:1.0      idle     abc123-def4-5678-...                  ~/myproject
dev:2.0      busy     xyz789-...                            ~/other
review:1.0   idle     (unregistered)                        ~
```

### Dispatch a task

```bash
# Short prompt
swarm dispatch dev:2.0 "Run the test suite and report failures"

# Long prompt from file
swarm dispatch dev:2.0 --file task.md
```

### Wait for completion

```bash
swarm monitor dev:2.0 --wait 600    # poll until idle, max 10 min
```

### Collect the result

```bash
RESULT=$(swarm collect dev:2.0)
echo "$RESULT"
```

Extracts the last assistant response from the session's JSONL log.

### Async mailbox

```bash
# Send a non-blocking message
swarm send dev:2.0 "Results ready at /tmp/analysis.json"

# Check your inbox
swarm inbox              # read and clear
swarm inbox --peek       # read without clearing
```

## Patterns

### Fan-out: parallel tasks

```bash
swarm dispatch dev:1.0 "Task A"
swarm dispatch dev:2.0 "Task B"
swarm dispatch dev:3.0 "Task C"

swarm monitor dev:1.0 --wait 600
swarm monitor dev:2.0 --wait 600
swarm monitor dev:3.0 --wait 600

A=$(swarm collect dev:1.0)
B=$(swarm collect dev:2.0)
C=$(swarm collect dev:3.0)
```

### Pipeline: sequential handoff

```bash
swarm dispatch dev:1.0 "Generate test data, save to /tmp/data.json"
swarm monitor dev:1.0 --wait 300

swarm dispatch dev:2.0 "Validate /tmp/data.json and report issues"
swarm monitor dev:2.0 --wait 300
```

### Supervised: check before continuing

```bash
swarm dispatch dev:1.0 "Analyze the auth module for security issues"
swarm monitor dev:1.0 --wait 600

ANALYSIS=$(swarm collect dev:1.0)
# Review analysis, then decide next steps
```

## Architecture

```
tmux sessions:
  dev:1   dev:2   dev:3   review:1   ops:1
    |       |       |         |         |
    +-------+-------+---------+---------+
                    |
              ~/.cc-swarm/
              +-- agents/       # Agent registry (JSON per pane)
              +-- mailbox/      # Async message inboxes
              +-- dispatches/   # Dispatch logs
              +-- tasks/        # Task files (prompt + result)
```

### How it works

1. **Hooks** register each CC session at startup, track idle/busy on every prompt submission
2. **`swarm list`** scans tmux panes for CC processes, merges with registry data
3. **`swarm dispatch`** uses tmux `send-keys` (short prompts) or named `paste-buffer` (long prompts) to deliver work
4. **`swarm collect`** parses the session's JSONL log to extract the last assistant response
5. **Status detection** uses hook-reported status (primary) with pane content heuristic (fallback)

### Named paste buffers

Fan-out dispatches use named tmux buffers (`swarm_PID_TIMESTAMP`) to prevent race conditions when sending to multiple agents concurrently.

## Plugin Structure

```
cc-swarm/
+-- .claude-plugin/
|   +-- plugin.json
+-- scripts/
|   +-- swarm                  # Main CLI (~750 lines bash)
+-- hooks/
|   +-- hooks.json             # SessionStart, UserPromptSubmit, Stop
|   +-- register-agent.sh     # Hook handler
+-- skills/
|   +-- swarm/
|       +-- SKILL.md           # Teaches Claude the swarm protocol
+-- docs/
    +-- logo.png
```

## Command Reference

| Command | Description |
| --- | --- |
| `swarm list` | Show all CC sessions with status |
| `swarm dispatch <target> <prompt>` | Send prompt to a CC session |
| `swarm dispatch <target> --file <path>` | Send long prompt from file |
| `swarm monitor <target>` | Capture pane output |
| `swarm monitor <target> --wait [timeout]` | Block until idle |
| `swarm collect <target>` | Get last assistant response |
| `swarm status` | Dashboard of all agents |
| `swarm send <target> <msg>` | Send async message to inbox |
| `swarm inbox` | Read and clear your inbox |
| `swarm inbox --peek` | Read without clearing |
| `swarm register-all` | Force-register all CC sessions |

## Non-goals

- Launching new CC sessions (use [claude-session-driver](https://github.com/jessevdk/claude-session-driver) for that)
- Managing permissions of other sessions
- MCP server or web dashboard
- Cross-machine coordination (just use SSH)

## License

MIT
