# QA Log Protocol

Shared protocol for inter-agent question-answer persistence.
All project agents read/write the same `qa_log.md` in the project task directory.

## File Location

```
~/.claude-swarm/tasks/{project_id}/qa_log.md
```

One file per project, append-only.
The planner writes answers; execution agents write questions.

## Entry Format

```markdown
## [{HH:MM}] {asker_role} -> {answerer_role}
Q: {question}
A: {answer}
Ref: {source — exemplar paper section, template rule, or "judgment"}
```

Example:

```markdown
## [14:32] method_writer -> planner
Q: Should the threat model use optimization or game-theoretic framing?
A: Optimization. BlueSuffix Section 3.1 uses bi-level optimization — follow that.
   Game-theoretic framing overcomplicates when there's no explicit adversary model.
Ref: BlueSuffix Section 3.1 (arxiv 2410.20971)
```

## Deduplication Protocol

Before asking the planner a question, execution agents MUST:

```bash
grep -i "{keyword}" ~/.claude-swarm/tasks/{project_id}/qa_log.md
```

If a relevant entry exists:
- Read the answer.
- If it fully resolves your question, do NOT ask again.
- If it partially resolves, reference it: "Re: [14:32] entry — I understand X, but what about Y?"

## Agent Responsibilities

### Planner (answerer)

1. Answer from loaded context (exemplar papers, Cong Wang template, taste ranking).
2. Append entry to qa_log.md after every answer.
3. On compaction recovery: read qa_log.md to know what was already communicated.
4. On duplicate question: reply with "See qa_log.md [{HH:MM}]" instead of re-answering.

### Execution Agents (askers)

1. Grep qa_log.md before asking.
2. After receiving an answer, verify it appears in qa_log.md (planner logs it).
3. On compaction recovery: read qa_log.md entries where you are the asker to restore context.
4. Track `qa_asked` count in your state JSON.

## State JSON Integration

Each agent's `{role}_state.json` includes:

```json
{
  "qa_asked": 3,
  "qa_topics": ["framing", "notation", "baseline-choice"],
  "last_qa_at": "2026-03-29T16:00:00Z"
}
```

The planner's `planner_state.json` includes:

```json
{
  "qa_count": 12,
  "qa_by_agent": {
    "method_writer": 5,
    "story_writer": 3,
    "experiment_agent": 3,
    "survey_agent": 1
  },
  "last_qa_from": "method_writer",
  "last_qa_topic": "formalization framing"
}
```

## Review Loop Integration

During review-revise cycles, the coordinator routes reviewer feedback to writers.
Writers may need planner guidance to interpret feedback.
These QA entries get tagged with the review round:

```markdown
## [18:45] method_writer -> planner (review_r2)
Q: Reviewer says "formalization is too abstract." Should I add a running example?
A: Yes. See DSN Section III-B — they introduce a running example after Definition 1.
   Add one concrete instance after the first formal definition.
Ref: DSN Section III-B (arxiv 2305.02605)
```

The `review_loop_state.json` cross-references:

```json
{
  "round": 2,
  "qa_during_round": ["18:45 method_writer"]
}
```

## Compaction Recovery

qa_log.md is the authoritative record.
After compaction, any agent can reconstruct the full QA history by reading it.
No agent needs to remember QA interactions in context -- the file is the memory.

Recovery priority for each agent:
1. Own state JSON (phase, progress)
2. qa_log.md (what was communicated)
3. Own outputs (what was produced)
4. plan.md (the master contract)
