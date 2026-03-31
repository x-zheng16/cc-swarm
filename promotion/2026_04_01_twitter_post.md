# Twitter/X Post Draft

## Option 1 (Technical)

CC Swarm -- peer-mesh multi-agent coordination for @anthropics Claude Code.

Every agent gets its own tmux window, full 200k context, full autonomy.
Dispatch tasks, exchange binding code reviews, merge branches, monitor liveness -- all through a single CLI.

Pure bash. Zero dependencies beyond tmux + jq.
190 tests. 40+ commands. ~3,200 lines.

Compared to OMC (182k TS), Claude Squad (6k Go), Gas Town (12k Go) -- CC Swarm does structured task lifecycle + binding review protocol in 3,200 lines of bash.

github.com/x-zheng16/cc-swarm

## Option 2 (Story-driven)

I run 25 Claude Code agents simultaneously on one laptop.

Each agent is an independent session with its own 200k-token context window.
They dispatch tasks to each other, exchange binding code reviews, and merge branches -- all coordinated through CC Swarm, a pure-bash CLI.

No TypeScript runtime. No Docker. No npm.
Just bash + tmux + jq.

The review protocol alone changed how I think about multi-agent QA: verdicts are gates, not suggestions. An agent cannot proceed until the reviewer says ACCEPT.

github.com/x-zheng16/cc-swarm

## Option 3 (Feature-focused thread starter)

CC Swarm: multi-agent coordination for Claude Code, the way Unix intended.

Thread:

1/ Task lifecycle: create, dispatch, track, update, collect. Structured envelopes with JSON metadata. No state held in memory -- everything is plain files.

2/ Binding code review: ACCEPT/REVISE/REJECT verdicts with auto-incrementing rounds. The reviewer is a gatekeeper. No cherry-picking feedback.

3/ Monitor agent: a dedicated watchdog that detects idle, stuck, and permission-blocked agents. Auto-nudges or escalates.

4/ DAG workflows: declare task dependencies in JSON, let swarm schedule execution across agents. Fan-out, fan-in, resume after interruption.

5/ Broadcast: ship a new feature? `swarm broadcast "changelog..."` sends to all idle agents at once. They learn the new capability immediately.

github.com/x-zheng16/cc-swarm
