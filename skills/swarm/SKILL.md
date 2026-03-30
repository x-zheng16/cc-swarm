---
name: swarm
description: Coordinate with other Claude Code sessions running in tmux windows. Use when you need to delegate tasks to other agents, check their status, collect results, or request reviews.
---

# CC Swarm v2 -- Multi-Agent Coordination

You can coordinate with other Claude Code sessions running in tmux windows using the `swarm` CLI.
Each CC session is a peer agent in a full-mesh network.
Teams and roles provide organizational structure, but any agent can talk to any other.

## Quick Reference

| Command | What it does |
| --- | --- |
| `swarm list [-v]` | Show registered agents (-v adds session_id) |
| `swarm status` | Dashboard of all agents |
| `swarm launch <session> [options]` | Launch CC sessions sequentially in tmux |
| `swarm task create --id X --from P --to P` | Create a structured task |
| `swarm task status <id>` | Show task state |
| `swarm task list [--state S]` | List tasks, optionally filtered |
| `swarm dispatch --task <id>` | V2 dispatch (target from envelope) |
| `swarm dispatch <target> "prompt"` | V1 dispatch (simple, no tracking) |
| `swarm dispatch <target> --file <path>` | V1 dispatch from file |
| `swarm review <task_id> --reviewer <pane>` | Request cross-agent review |
| `swarm monitor <target> --wait 300` | Block until target finishes |
| `swarm collect <target>` | Get last assistant response text |
| `swarm card [<target>]` | Show agent card |
| `swarm card set-role <target> <role>` | Set role (worker, lead, monitor) |
| `swarm card set-team <target> <team>` | Assign to team |
| `swarm card set-caps <target> <c1,c2>` | Set capabilities |
| `swarm team list\|create\|add\|show\|delete` | Team management |
| `swarm topology` | Show full topology |
| `swarm send <target> "msg"` | Async message to inbox |
| `swarm inbox [--peek]` | Read your inbox |
| `swarm ask <target> "question"` | Send tracked QA question |
| `swarm reply <qa_id> "answer"` | Reply to a QA question |
| `swarm qa [--state S]` | List QA records |
| `swarm run <dag.json>` | Execute a DAG workflow |
| `swarm monitor-start [--session S]` | Launch the monitor agent |
| `swarm monitor-status` | Show monitor report |
| `swarm register-all` | Bulk-register existing CC sessions |

## Identity and Teams

Every agent has a card at `~/.claude-swarm/agents/{pane}.json` with:
- `role`: worker (default), lead, or monitor
- `team`: team name (e.g., "backend")
- `capabilities`: what you can do (e.g., ["coding", "testing"])
- `current_task`: task_id you are working on (set by dispatch, cleared on idle)

Check your own card: `swarm card` (auto-detects your pane).

Teams are defined in `~/.claude-swarm/topology.json`.
Team leads can spawn new agents.
The monitor is a special agent that watches all others.

You have full mesh capability: you can talk to any agent regardless of team.
Teams are organizational, not communication boundaries.

## Receiving Tasks

When you receive a task via `swarm dispatch --task`:

1. You see: `Read and execute the task in ~/.claude-swarm/tasks/{task_id}/prompt.md`
2. Read `prompt.md` for instructions.
3. Read `envelope.json` from the same directory for metadata (who sent it, what type, where to write results).
4. **Verify relevance**: does this task match your session's purpose? If not, reject it and notify the sender.
5. Execute the task.
6. Write your output to the `result_path` specified in envelope.json.
7. Go idle. The system detects completion automatically.

## Sending Tasks (V2 Protocol)

The structured way to delegate work:

```bash
# 1. Create the task
swarm task create --id 20260328_analyze_data \
    --from mbp:1.0 --to mbp:5.0 \
    --type task --prompt "Analyze experiment results in /tmp/data.json"

# 2. Dispatch (target read from envelope's "to" field)
swarm dispatch --task 20260328_analyze_data

# 3. Wait
swarm monitor mbp:5.0 --wait 600

# 4. Read result
cat ~/.claude-swarm/tasks/20260328_analyze_data/result.md
```

For quick, untracked tasks, V1 dispatch still works:

```bash
swarm dispatch mbp:5.0 "Run the test suite and report failures"
```

### Task Lifecycle

```
created -> dispatched -> running -> completed | failed | stuck
```

The CLI manages transitions.
Status is tracked in `~/.claude-swarm/tasks/{task_id}/status.json`.
Check with: `swarm task status <task_id>`.

V2 dispatch automatically appends a notification instruction to prompt.md.
The receiving agent will `swarm send <dispatcher> "done: <task_id>"` when finished.
The dispatcher sees this in their inbox (`swarm inbox`).

### Task ID Convention

Format: `{YYYYMMDD}_{slug}` (e.g., `20260328_auth_refactor`).
Review rounds: append `_review_r1`, `_r2`, etc.

## Review Exchange

**NEVER review your own work.**
Generator-evaluator separation is critical.
Always dispatch reviews to a different agent.

```bash
# Request a review of your completed task
swarm review 20260328_my_draft --reviewer mbp:14.0

# With custom artifact (review something outside the task dir)
swarm review 20260328_my_draft --reviewer mbp:14.0 \
    --artifact ~/projects/research/paper/main.tex
```

This creates `20260328_my_draft_review_r1` and dispatches it to the reviewer.
If r1 exists, it auto-creates r2, r3, etc.

### Review Format

When reviewing, write your output to `result_path` with this structure:

```markdown
# Review: {what you reviewed}

## Verdict: MAJOR_REVISION | MINOR_REVISION | ACCEPT

## Critical Issues (must fix)
1. ...

## Important Issues (should fix)
1. ...

## Minor Issues (nice to fix)
1. ...

## Strengths
1. ...

## Summary
One paragraph assessment.
```

### Review Flow

```
Author finishes work
  -> swarm review <task_id> --reviewer <other_agent>
Reviewer reads artifact, writes structured review
  -> swarm send <author> "Review done, read result_path"
Author reads review, revises
  -> If needed: swarm review <task_id> --reviewer <other_agent>  (creates _r2)
```

## Sprint Contracts

Before a large task, establish expectations with your dispatcher:
- What exactly is the deliverable?
- Where does it go (result_path)?
- What quality bar?
- What timeout?

Write the agreement into prompt.md so both parties share the same expectations.
This prevents the common failure: agent does great work, but not what was asked.

## QA Protocol

For bidirectional question-answer exchanges between agents.
Used when an agent needs clarification from another agent.

```bash
# Agent asks a question (creates tracked QA record, notifies target via inbox)
swarm ask mbp:lead.0 "Should we use the streaming API or batch?"
# -> qa_20260329_100253_bea634

# Target reads inbox, sees [QA] message with reply instructions
swarm inbox

# Target replies (notifies asker via inbox)
swarm reply qa_20260329_100253_bea634 "Streaming. See the design doc at /tmp/api_design.md"

# List all QA records
swarm qa
swarm qa --state pending    # only unanswered questions
```

QA records are stored in `~/.claude-swarm/qa/` with full audit trail (who asked, when, who answered, when).
Team leads should log QA interactions to `qa_log.md` for compaction recovery.

## Async Mailbox

For non-blocking messages between agents.

```bash
swarm send mbp:5.0 "Results ready at /tmp/analysis.json"
swarm inbox            # read and clear
swarm inbox --peek     # read without clearing
```

## Monitor Agent

A dedicated CC session watches all agents and proactively helps.
Launch it: `swarm monitor-start`.
Check its report: `swarm monitor-status`.

If you are stuck, you can ask the monitor for help:

```bash
swarm send mbp:monitor.0 "I am stuck on: <describe issue>"
```

If the monitor sends you a message, treat it as a suggestion, not a command.
It observes and nudges; it does not have authority over you.

## DAG Workflows

Declare task dependencies in JSON, let swarm handle scheduling:

```json
{
  "id": "my-workflow",
  "max_parallel": 3,
  "tasks": {
    "design":    {"target": "mbp:1.0", "prompt": "Design the system"},
    "implement": {"target": "mbp:2.0", "depends_on": ["design"], "outputs": ["src/main.py"]},
    "test":      {"target": "mbp:3.0", "depends_on": ["design"]},
    "integrate": {"target": "mbp:1.0", "depends_on": ["implement", "test"], "join": "and"}
  }
}
```

```bash
swarm run workflow.json --dry-run   # validate
swarm run workflow.json             # execute
swarm run workflow.json --resume    # resume after interruption
```

## Important Rules

- **Target by window NAME**, never by index. Indices shift when windows are rearranged.
- **Fresh window per task.** Never dispatch to a window with an existing active session.
- **File reference for long prompts.** Use `--file` or `--task`, never paste raw.
- **Files for shared data.** Agents share the filesystem. Write to files for data exchange.
- **Sequential launches only.** `swarm launch` enforces this. Never launch CC sessions in parallel.
- **Context resets over compaction.** If your context is getting large, write state to files and ask for a fresh session with a continuation prompt.
- **Status is heuristic.** If `swarm status` shows "unknown", the agent may be at an unusual state.
- **`swarm list` shows registered agents only.** Agents auto-register via hooks. For pre-existing sessions without hooks, run `swarm register-all` to bulk-register.

## Launching Sessions

```bash
swarm launch xz --count 3             # 3 sessions in xz
swarm launch xz -n researcher         # named agent
swarm launch xz --cmd cc2 --count 2   # use cc2 account
swarm launch xz -n worker -m sonnet   # with model override
```

Sessions launch one at a time (180s timeout each).
Readiness: version number visible + idle status detected.

## Targeting

Targets use tmux pane addressing: `session:window.pane`

Examples: `mbp:5.0`, `xz:researcher.0`

Run `swarm list` to see all valid targets.
