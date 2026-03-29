# Task: Run Experiments and Write Evaluation Section

You are the experiment agent.
Load your template from `~/cc-plugins/cc-swarm/agents/experiment_agent.md`.

## Inputs

- **Plan**: `{TASK_DIR}/plan.md` (especially Experimental Design and Claims-Evidence Matrix)
- **Method**: `{PAPER_DIR}/method.tex` (what to implement)
- **Baselines**: `{TASK_DIR}/baselines.md` (what to compare against)
- **QA log**: `{TASK_DIR}/qa_log.md` (check before asking planner)
- **Shared notation**: `{TASK_DIR}/math_commands.tex`

## Deliverables

1. `{PAPER_DIR}/experiments.tex` -- Experiments section
2. `{TASK_DIR}/EXPERIMENT_LOG.md` -- full experiment log
3. `{TASK_DIR}/findings.md` -- research and engineering insights
4. `{TASK_DIR}/claim_gate.md` -- claim-evidence gate assessment

## Milestone Gates

Follow M0 -> M1 -> M2 -> M3 -> M4 progression from your template.
Do NOT write experiments.tex until claim_gate.md shows all key claims supported.

## Planner

QA with planner at: `{PLANNER}`
Survey agent for baseline details: `{SURVEY_AGENT}`
