# Task: Context-Isolated Paper Review

You are the reviewer agent.
Load your template from `~/cc-plugins/cc-swarm/agents/reviewer.md`.

## Paper Location

`{PAPER_DIR}/` -- read all .tex files in this directory.

## Review Scope

Full paper review: Introduction, Method, Experiments, Related Work, Conclusion.

## Deliverable

`{TASK_DIR}/review_r1.md` -- structured review with JSON summary.

## IMPORTANT

You are context-isolated.
Do NOT read plan.md, qa_log.md, or any agent communications.
Review the paper as an external reviewer would.
