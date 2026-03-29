# Task: Write Research Plan

You are the planner agent.
Load your template from `~/cc-plugins/cc-swarm/agents/planner.md` and follow the Startup sequence.

## Project

- **Research contract**: `{TASK_DIR}/research_contract.md`
- **Task directory**: `{TASK_DIR}/`
- **Paper directory**: `{PAPER_DIR}/`

## Deliverables

1. `{TASK_DIR}/plan.md` -- the research plan (follow template in your agent instructions)
2. Style guide section within plan.md (extracted from exemplar papers)
3. `{TASK_DIR}/qa_log.md` -- initialize the empty QA log
4. `{TASK_DIR}/math_commands.tex` -- shared notation
5. Brief orientation messages to each execution agent (via `swarm send`)

## Agent Panes

- Story Writer: `{STORY_WRITER}`
- Survey Agent: `{SURVEY_AGENT}`
- Method Writer: `{METHOD_WRITER}`
- Experiment Agent: `{EXPERIMENT_AGENT}`

After writing plan.md, send each agent a 2-3 bullet orientation tailored to their role.
Then go idle -- you will receive QA questions as the agents work.
