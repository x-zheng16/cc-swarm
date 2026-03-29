# Agent Template Audit Report

## Executive Summary

Our 6-template system is significantly more taste-aware and structurally sophisticated than any open-source auto-research system reviewed.
The per-agent separation of concerns, the echo map concept, the Cong Wang template enforcement, and context-isolated reviewing are genuinely novel features that no competitor matches.
However, we have meaningful gaps in: LaTeX compilation/validation loops, automated citation management, experiment failure recovery, VLM-based figure review, multi-reviewer ensemble, and claims-evidence traceability.

## Comparison Matrix

| Dimension                         | Our System              | AI Scientist v2         | AI Scientist v1         | Agent Laboratory        | ARIS                    | OpenResearcher          | DATAGEN                 |
|-----------------------------------|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|
| Agent specialization              | 6 dedicated agents      | monolithic pipeline     | monolithic pipeline     | 4 role-play agents      | 40+ modular skills      | service pipeline        | 9 agents + router       |
| Writing taste enforcement         | exemplar-driven style   | generic tips            | per_section_tips dict   | professor dialogue      | shared-references       | none                    | none                    |
| Review isolation                  | strict context wall     | none (same LLM)         | none (same LLM)         | none                    | cross-model (GPT)       | self-critic only        | quality-review agent    |
| Review ensemble                   | single reviewer         | ensemble + meta-review  | ensemble + meta-review  | 3 persona reviewers     | single + loop           | single                  | single                  |
| LaTeX compilation loop            | not present             | compile + chktex + fix  | compile + chktex + fix  | not present             | not present             | N/A                     | N/A                     |
| Citation management               | manual (survey agent)   | automated S2 + rounds   | automated S2 + aider    | not present             | DBLP auto-fetch         | not present             | not present             |
| VLM figure review                 | not present             | yes (img review)        | not present             | not present             | not present             | not present             | not present             |
| Experiment stage management       | single-phase            | 4-stage (impl->tune->creative->ablation) | single-phase | multi-phase dialogue | claim-driven blocks     | N/A                     | process agent routing   |
| Compaction recovery               | state files             | journal + checkpoint    | not present             | not present             | REVIEW_STATE.json       | not present             | not present             |
| Claims-evidence matrix            | echo map (narrative)    | not present             | not present             | not present             | full claims matrix      | not present             | not present             |
| Cross-agent QA                    | swarm ask/send          | not applicable          | not applicable          | dialogue turns          | not applicable          | not applicable          | process agent routing   |
| Failure interpretation            | not present             | not present             | not present             | not present             | per-block failure plan  | not present             | not present             |
| Page limit enforcement            | not present             | compile + detect pages  | not present             | not present             | MAX_PAGES constant      | N/A                     | N/A                     |
| Novelty verification              | not present             | not present             | not present             | not present             | dedicated skill         | not present             | not present             |
| Experiment logging                | EXPERIMENT_LOG.md       | JSON summaries          | notes.txt               | in-context history      | structured log + findings | not present            | note agent              |

## Per-Template Analysis

### 1. Planner (`planner.md`)

**Gaps:**

1. **No claims-evidence matrix.**
ARIS has a formal `Claims-Evidence Matrix` that maps each claim to specific evidence, status, and section.
Our echo map covers narrative coherence but not evidentiary grounding.
A reviewer asks "where is the evidence for claim X?" and the echo map cannot answer that -- it only tracks where concepts appear, not what supports them.

2. **No novelty verification step.**
ARIS has a dedicated `novelty-check` skill that searches arXiv, Semantic Scholar, and uses cross-model verification before committing to a research direction.
Our planner reads the research contract but never validates that the claimed gap actually exists.

3. **No failure/pivot protocol.**
AI Scientist v2's `AgentManager` has explicit stage transitions with `ready_for_next_stage` evaluation and `missing_criteria` tracking.
Our planner has no protocol for what happens when the method doesn't work, experiments fail, or a stronger baseline surfaces mid-project.

4. **No compute budget planning.**
ARIS's experiment plan template includes explicit GPU-hour estimates, run order with milestones, and cost per block.
Our planner's Experimental Design section lists baselines and metrics but not the execution plan.

**Strengths:**

1. **Taste context loading is unique.** No other system reads actual exemplar papers to extract writing style. AI Scientist v1 has `per_section_tips` but they are generic one-liners, not extracted from the PI's own publications.

2. **QA log system is well-designed.** The `qa_log.md` with deduplication, sourcing, and timestamping is more structured than any competitor's inter-agent communication.

3. **Proactive guidance** to downstream agents after plan completion -- no other system does this.

4. **Decision authority boundaries** are explicit and practical. No competitor separates tactical vs strategic decisions this clearly.

**Suggested Improvements:**

Add a Claims-Evidence Matrix section to the plan template (after Echo Map):

```markdown
## Claims-Evidence Matrix
| # | Claim | Required Evidence | Status | Section |
|---|-------|-------------------|--------|---------|
| C1 | [main claim] | [Table 1: method vs baselines] | Pending | Sec III, V |
| C2 | [supporting claim] | [Ablation Table 2] | Pending | Sec V |

## Failure Interpretation
| Claim | If Evidence Negative | Pivot Plan |
|-------|---------------------|------------|
| C1 | Method does not outperform -> reframe as analysis contribution | Escalate to Xiang |
| C2 | Component X doesn't help -> drop from method, simplify | Planner decides |
```

Add a Compute Budget section:

```markdown
## Compute Budget
| Block | Runs | Est. GPU-hours | Priority |
|-------|------|----------------|----------|
| Baseline reproduction | 3 | ~4h | MUST-RUN |
| Main method | 5 seeds | ~20h | MUST-RUN |
| Ablation suite | 8 variants | ~16h | MUST-RUN |
| Extended analysis | 3 | ~6h | NICE-TO-HAVE |
**Total**: ~46 GPU-hours on [hardware]
```

Add a Novelty Gate before writing the plan:

```markdown
## 2.5. Novelty Gate

Before writing the plan, verify the claimed gap still exists:
1. Search Semantic Scholar for the 3 most specific claims in the research contract.
2. If a paper from the last 6 months substantially overlaps, flag to Xiang immediately.
3. Record search results in `novelty_check.md`.
Do NOT proceed to plan writing if novelty is unverified.
```

---

### 2. Story Writer (`story_writer.md`)

**Gaps:**

1. **No self-refinement loop.**
AI Scientist v1 has explicit `refinement_prompt` and `second_refinement_prompt` per section, with error checking.
AI Scientist v2 has `n_writeup_reflections=3` loops where it re-reads, identifies issues, and rewrites.
Our story writer writes once and waits for the reviewer -- no self-correction pass.

2. **No contribution bullet point format guidance.**
AI Scientist v1's Introduction tips explicitly mention: "New trend: specifically list your contributions as bullet points."
Our template describes the Cong Wang 8-step structure but doesn't specify how contributions are formatted (numbered? bulleted? inline?).

3. **No title generation guidance.**
AI Scientist v2 has explicit title tips: "Title should be catchy and informative... try to keep it under 2 lines."
Our story writer is assigned "Title" but has zero guidance on how to write one.

4. **No abstract length/format constraint.**
ARIS's paper-write skill specifies "one continuous paragraph" for the abstract.
Our template says "1 paragraph" but doesn't enforce constraints.

**Strengths:**

1. **Fractal structure concept** (Title -> Abstract -> Introduction -> Full Paper) is elegant and not found in any competitor.

2. **Bridge principle (承上启下)** with concrete transition examples is significantly better than any competitor's writing guidance.

3. **Echo map responsibility** -- explicitly assigning narrative coherence ownership to the story writer is a design pattern no competitor has.

**Suggested Improvements:**

Add a self-refinement step after each section:

```markdown
# Self-Check Before Sending to Reviewer

After completing each section, perform one self-check pass:
1. Re-read the section with fresh eyes.
2. Check: does every paragraph end with a forward pointer or begin with a backward reference?
3. Check: are all Key Observations from plan.md mentioned where the echo map requires?
4. Check: are there any unsupported claims (numbers, comparisons) that need experiment data?
5. Mark any issues with `[SELF_CHECK: issue]` and fix them before notifying the planner.
```

Add title writing guidance:

```markdown
# Writing the Title

The title is the most-read sentence in the paper. Rules:
1. Under 15 words. Under 2 lines in the template.
2. Include the core mechanism or insight, not just the domain.
3. Avoid: generic words ("Novel", "Efficient", "Towards"), question format, colon-heavy titles.
4. Pattern from exemplars: "[Mechanism]: [What it achieves] for/via [Domain]"
   - e.g., "BlueSuffix: Certified Robustness of LLM Outputs via Randomized Smoothing"
5. Draft 3-5 candidates. QA with planner to select.
```

---

### 3. Survey Agent (`survey_agent.md`)

**Gaps:**

1. **No automated citation fetching.**
AI Scientist v1 and v2 both have multi-round Semantic Scholar search loops with automated BibTeX extraction and deduplication.
ARIS's paper-write skill has `DBLP_BIBTEX = true` for automated real BibTeX from DBLP/CrossRef.
Our survey agent uses manual tools (`tvly search`, Semantic Scholar API) but has no structured citation-fetch-verify loop.

2. **No citation verification protocol.**
AI Scientist v1 explicitly checks every `\cite{}` against `references.bib` and prompts fixes for mismatches.
Our survey agent says "NEVER fabricate citations" but doesn't specify HOW to verify -- no checksum, no BibTeX validation step.

3. **No coverage metrics.**
The "minimum 25 papers" guideline is arbitrary.
No other system has coverage metrics either, but ARIS's shared-references approach categorizes citation purposes (7 categories from AI Scientist).
Our survey agent should ensure coverage per category, not just total count.

4. **No snowball search depth limit.**
The "snowball search" instruction has no termination criterion.
Could lead to unbounded exploration.

**Strengths:**

1. **Three-output structure** (related_work.tex, baselines.md, target_papers.md) with must-read / must-cite / nice-to-cite tiers is more structured than any competitor.

2. **Positioning language examples** (good vs bad) are concrete and actionable -- no competitor provides anti-patterns.

3. **Cong Wang philosophy** for related work (never say others are worse) is a genuine quality differentiator.

**Suggested Improvements:**

Add a citation verification loop:

```markdown
# Citation Verification

After completing related_work.tex:
1. Extract all `\cite{}` and `\citet{}` keys.
2. For each key, verify:
   - BibTeX entry exists in references.bib
   - Author names match the in-text reference
   - Year is correct
   - Venue is correct (check via Semantic Scholar API)
3. Log verification results in `citation_audit.md`.
4. Any unverified citation gets marked with `% [UNVERIFIED]` comment in .tex.
```

Add structured search with categories:

```markdown
# Citation Coverage Categories

Ensure at least one paper per category:
1. **Direct competitors** -- methods solving the same problem (-> baselines.md)
2. **Methodological ancestors** -- techniques our method builds on
3. **Application-domain context** -- the broader domain significance
4. **Evaluation methodology** -- how this type of work is typically evaluated
5. **Theoretical foundations** -- formal results our approach relies on
Track coverage in target_papers.md with a category column.
```

---

### 4. Method Writer (`method_writer.md`)

**Gaps:**

1. **No notation consistency check.**
AI Scientist v1 checks for unenclosed math symbols and LaTeX syntax errors via `chktex`.
Our method writer says "Be consistent" but has no verification mechanism.

2. **No theorem/proof workflow.**
The template mentions "proof goes in Security Analysis" but doesn't specify:
- How to state theorems (formal statement vs informal claim)
- When to include proof sketches vs full proofs
- How to handle failed proofs (flag to planner? weaken the claim?)
ARIS's `proof-writer` and `formula-derivation` skills are dedicated to this.

3. **No algorithm pseudocode format standard.**
The template shows `\begin{algorithm}` but doesn't specify:
- Line numbering style
- Input/Output format
- When to use pseudocode vs mathematical formulation
AI Scientist v1 at least mentions "algorithms/protocols are presented" in exemplar extraction.

4. **No figure specification format.**
The `framework_figure_spec.md` is mentioned but not templated.
The method writer doesn't know what a good spec looks like.

**Strengths:**

1. **WHY -> HOW -> WHY-IT-WORKS pattern** is the best-articulated method writing framework across all systems reviewed. AI Scientist v1 just says "What we do. Why we do it." -- ours is a structured 3-part template with concrete examples.

2. **Progressive extension (递进) concept** for Section IV is unique and captures a real pattern in security papers.

3. **QA_PENDING markers** allow non-blocking writing while waiting for planner responses -- a practical pattern no competitor has.

**Suggested Improvements:**

Add a notation consistency check:

```markdown
# Post-Draft Checks

After completing method.tex, run these checks:

## Notation Audit
1. List every mathematical symbol used (extract from .tex via regex or manual scan).
2. Verify each symbol is defined before first use.
3. Verify no symbol is used with two different meanings.
4. Record the notation table in `notation_audit.md` for the planner.

## Algorithm Format Standard
- Use `\begin{algorithm}[t]` with `\caption{}` and `\label{alg:X}`
- Input/Output on first two lines: `\Require`, `\Ensure`
- Number all lines
- Reference algorithms as `Algorithm~\ref{alg:X}`
```

Add a framework figure spec template:

```markdown
# Framework Figure Specification Template

Write `framework_figure_spec.md` with:
```markdown
## Figure: {name}
- **Purpose**: What the reader should understand from this figure
- **Components**: [list of boxes/nodes with labels]
- **Flows**: [arrows between components, labeled with data/signals]
- **Phase mapping**: Phase 1 = [components A,B], Phase 2 = [components C,D]
- **Visual style**: [tikz / draw.io / matplotlib / manual illustration]
- **Reference**: "As shown in Figure~\ref{fig:framework}"
- **Exemplar**: [closest figure from the 6 exemplar papers, e.g., "similar to BlueSuffix Fig 1"]
```
```

---

### 5. Experiment Agent (`experiment_agent.md`)

**Gaps:**

1. **No staged execution with gates.**
AI Scientist v2 has 4 explicit stages (initial_implementation -> baseline_tuning -> creative_research -> ablation_studies), each with `max_iterations`, goal evaluation, and `ready_for_next_stage` gating.
ARIS has milestone-based run order (M0: Sanity -> M1: Baselines -> M2: Main -> M3: Ablation) with decision gates.
Our experiment agent runs experiments but has no staged progression or go/no-go gates.

2. **No failure interpretation protocol.**
ARIS's experiment plan has explicit "Failure interpretation: If negative, what does it mean?" per block.
Our agent says "log it and QA with planner" but doesn't specify how to interpret or respond to failures.
What if ALL baselines beat us? What if ablations show a component doesn't help? These need pre-planned responses.

3. **No reproducibility verification.**
AI Scientist v1 explicitly checks: "Only includes results that have actually been run and saved in the logs. Do not hallucinate results that don't exist."
Our agent says "NEVER fabricate numbers" but doesn't specify HOW to verify -- no config-to-table cross-check, no reproduction command logging.

4. **No WandB/logging integration.**
ARIS's run-experiment skill has explicit W&B integration with `wandb.init`, `wandb.log`, and run URL tracking.
Our agent mentions `results/` directory but no structured logging framework.

5. **No figure quality control.**
AI Scientist v2 has VLM-based figure review that examines each plot's content, caption accuracy, and text reference alignment.
AI Scientist v1 checks for duplicate figures, missing figures, and invalid figure references.
Our agent generates matplotlib figures but has no quality check.

6. **No success criteria per experiment.**
ARIS specifies "Success criterion: > 2% accuracy over baseline" per block.
Our agent runs experiments without pre-defined thresholds for what counts as success.

**Strengths:**

1. **Code organization template** is cleaner than any competitor's -- explicit directory structure with configs, results, figures separation.

2. **EXPERIMENT_LOG.md** with timestamp + config + result + notes + status is well-structured (similar to ARIS's template but more concise).

3. **Handoff messages** to story writer and method writer with specific headline numbers is a practical coordination pattern.

4. **"Journal depth, conference presentation"** philosophy is a genuine strategic insight about experiment scale.

**Suggested Improvements:**

Add staged execution with decision gates:

```markdown
# Execution Stages

Follow this staged approach from plan.md's run order:

## Stage 0: Sanity Check
- Run a minimal experiment (1 seed, small data, few epochs)
- **Gate**: Does the pipeline run without errors? Does loss decrease?
- If FAIL: Fix code before proceeding. Do NOT run full experiments on broken code.

## Stage 1: Baseline Reproduction
- Reproduce all baselines from baselines.md
- **Gate**: Do our numbers match reported numbers within 2%?
- If FAIL: QA with survey agent for correct hyperparameters. Log discrepancy.

## Stage 2: Main Results
- Run full method on all datasets/tasks
- **Gate**: Does our method meet the success criteria from plan.md?
- If FAIL: Log in EXPERIMENT_LOG.md with hypothesis for why. QA with planner for pivot.

## Stage 3: Ablation & Analysis
- Run all ablation experiments
- **Gate**: Does each component contribute meaningfully?
- If a component doesn't help: notify planner immediately -- method may need simplification.

NEVER skip to Stage N+1 if Stage N gate fails.
```

Add success criteria and failure protocol:

```markdown
# Success Criteria (from plan.md)

Before running each experiment block, record:
- **Success threshold**: {metric} > {value} OR {delta} > {threshold}
- **Failure interpretation**: If negative, it means {interpretation}
- **Failure action**: {drop component / debug / QA with planner / pivot}

After each block, compare results against criteria and log verdict.
```

Add figure quality control:

```markdown
# Figure Quality Check

After generating each figure:
1. Does the figure have a title, axis labels, and legend?
2. Is the font size readable at conference column width?
3. Are colors colorblind-friendly? (avoid red-green only)
4. Does the figure tell a clear story without reading the caption?
5. Is the figure referenced in experiment.tex with `Figure~\ref{fig:X}`?
```

---

### 6. Reviewer (`reviewer.md`)

**Gaps:**

1. **No ensemble reviewing.**
AI Scientist v1 and v2 use `num_reviews_ensemble` (multiple reviews from different temperature samples) plus a meta-review that aggregates scores.
Agent Laboratory uses 3 distinct reviewer personas (harsh-experiments, harsh-impact, harsh-novelty).
Our reviewer is a single agent with a single perspective.

2. **No few-shot calibration.**
AI Scientist v1 uses `get_review_fewshot_examples()` to provide real review examples for calibration.
Our reviewer has score anchoring (8-10 = NeurIPS accept) but no concrete examples of what a 6 vs 8 review looks like.

3. **No VLM figure review.**
AI Scientist v2's `perform_vlm_review.py` does per-figure visual review: examining axis labels, legend accuracy, caption-figure alignment, and text reference adequacy.
Our reviewer reads TeX source but cannot visually verify figures.

4. **No LaTeX compilation verification.**
AI Scientist v1 and v2 compile the paper and check for errors as part of the review process.
Our reviewer reads TeX files but never verifies they compile.

5. **No structured JSON output.**
Both AI Scientist versions output reviews as parseable JSON with numeric scores for automated pipelines.
Our reviewer outputs markdown -- fine for humans but not for automated review loops.

6. **No reviewer bias control.**
AI Scientist v1 has explicit `reviewer_system_prompt_neg` (pessimistic) and `reviewer_system_prompt_pos` (optimistic) variants.
Our reviewer is always adversarial, which may miss genuine strengths.

**Strengths:**

1. **Context isolation** is the strongest design decision across all reviewed systems. No competitor enforces this -- AI Scientist reviews are done by the same LLM that wrote the paper with full context. Agent Laboratory's reviewers see the plan. Only our system creates a genuine information barrier.

2. **Two review types** (Research vs Writing) with separate criteria is more structured than any competitor's single-pass review.

3. **Round tracking** with max rounds (4 research, 2 writing) prevents infinite review loops -- a practical safeguard.

4. **Venue-calibrated standards** with explicit per-venue notes is not present in any competitor.

**Suggested Improvements:**

Add ensemble reviewing support:

```markdown
# Ensemble Review (when dispatched as ensemble)

The coordinator may dispatch 2-3 reviewer instances with different personas:
- **Persona A**: Harsh on experiments -- expects strong baselines and thorough ablations
- **Persona B**: Harsh on novelty -- asks "what is genuinely new here?"
- **Persona C**: Harsh on presentation -- expects perfect flow and notation

Each persona reviews independently. The coordinator aggregates.

If you are dispatched as a specific persona, focus your review on that dimension
while still covering all criteria.
```

Add structured output format for automated loops:

```markdown
# Machine-Readable Output (when requested)

If the task envelope includes `format: json`, output your review as:

```json
{
  "type": "research|writing",
  "verdict": "MAJOR_REVISION|MINOR_REVISION|ACCEPT",
  "scores": {
    "novelty": 7,
    "soundness": 8,
    ...
  },
  "overall": 42,
  "critical_issues": [
    {"section": "3.2", "line": 15, "issue": "...", "suggestion": "..."}
  ],
  "important_issues": [...],
  "minor_issues": [...],
  "strengths": [...],
  "questions": [...]
}
```

This enables automated review loops to parse scores and track improvement.
```

Add LaTeX compilation check:

```markdown
# Pre-Review Compilation Check

Before reviewing content, verify the paper compiles:
1. Run `pdflatex` + `bibtex` + `pdflatex` + `pdflatex` on main.tex
2. If compilation fails, report compilation errors as Critical Issues FIRST.
3. Check page count -- if over the venue limit, flag as Critical.
4. Only proceed to content review if the paper compiles successfully.
```

---

## Cross-Cutting Issues

### 1. No End-to-End Review Loop

ARIS has `auto-review-loop` that autonomously iterates: review -> fix -> re-review, up to MAX_ROUNDS, with persistent state, score tracking, and stop conditions.
Our system has a reviewer but no automated loop connecting reviewer feedback back to the writing agents.
The coordinator must manually route every review.

**Recommendation**: Add a `review_loop` protocol to the planner or create a coordinator template that:
- Dispatches reviewer after each writing milestone
- Parses review verdict
- Re-dispatches to the appropriate writer agent for fixes
- Tracks improvement across rounds
- Stops when verdict = ACCEPT or max rounds reached

### 2. No LaTeX Compilation Pipeline

AI Scientist v1 and v2 both have robust `compile_latex()` functions with:
- `pdflatex` + `bibtex` multi-pass
- `chktex` for style checking
- Duplicate figure/section detection
- Missing reference detection
- Error correction loops (up to `num_error_corrections=5`)

None of our agents handle LaTeX compilation.
This means broken TeX can propagate through the entire pipeline.

**Recommendation**: Either add compilation responsibility to the experiment agent (figures) and story writer (final assembly), or create a dedicated `latex_compiler` agent/utility.

### 3. No Shared BibTeX Management

AI Scientist v1 manages `references.bib` as a shared resource with deduplication, verification, and round-based addition.
ARIS fetches BibTeX from DBLP/CrossRef automatically.

In our system, the survey agent produces `target_papers.md` and `baselines.md`, but there is no shared `references.bib` that all writing agents reference.
This risks citation inconsistencies between agents.

**Recommendation**: The survey agent should produce `references.bib` as an additional output, and all writing agents should reference it.
Add a citation consistency check to the reviewer's protocol.

### 4. No Findings Log

ARIS has a dedicated `findings.md` that separates research findings from engineering findings, persists across sessions, and is read on every recovery.
Our EXPERIMENT_LOG.md captures what happened but not what was LEARNED.

**Recommendation**: Add a Findings section to EXPERIMENT_LOG.md or create a separate `findings.md` that the experiment agent updates after each verdict.

### 5. Missing Agent: Coordinator/Orchestrator

Every competitive system has an orchestration layer:
- AI Scientist v2: `AgentManager` with stage transitions
- Agent Laboratory: `ai_lab_repo.py` with multi-phase orchestration
- DATAGEN: `process_agent` that routes to other agents
- ARIS: skill chaining (`research-refine-pipeline`)

Our system assumes a human coordinator or an external dispatcher.
This is fine for the cc-swarm architecture, but the templates don't specify:
- What order agents should be activated
- What the handoff protocol looks like end-to-end
- What happens when an agent blocks waiting for another

**Recommendation**: Add a `WORKFLOW.md` document that specifies the DAG:
```
planner -> [survey_agent, method_writer] (parallel)
survey_agent -> experiment_agent (baselines)
method_writer -> experiment_agent (implementation)
method_writer -> story_writer (foreshadowing)
experiment_agent -> story_writer (conclusion data)
all_writers -> reviewer -> fix loop -> planner (final approval)
```

---

## Priority Improvements (ranked by impact)

1. **Add staged experiment execution with decision gates** (experiment_agent.md)
   Impact: prevents wasted compute on broken pipelines; catches method failures early.
   Every competitor with experiment management uses gates.
   Effort: add ~30 lines to experiment_agent.md.

2. **Add claims-evidence matrix to the plan** (planner.md)
   Impact: provides evidentiary grounding that the echo map lacks; directly maps to reviewer expectations.
   ARIS has this and it is their strongest structural innovation.
   Effort: add ~15 lines to plan template.

3. **Add self-refinement loops to writing agents** (story_writer.md, method_writer.md)
   Impact: catches obvious issues before the reviewer sees them; reduces review rounds.
   AI Scientist v2 uses 3 reflection loops with significant quality improvement.
   Effort: add ~20 lines per writing template.

4. **Add structured JSON review output** (reviewer.md)
   Impact: enables automated review-fix loops; makes score tracking programmatic.
   Both AI Scientist versions and Agent Laboratory use parseable review formats.
   Effort: add ~15 lines to reviewer.md.

5. **Create a shared references.bib workflow** (survey_agent.md, all writers)
   Impact: eliminates citation inconsistencies; reduces fabrication risk.
   AI Scientist and ARIS both centralize bibliography management.
   Effort: add ~10 lines to survey_agent.md, ~5 lines per writer.

6. **Add failure interpretation per experiment block** (experiment_agent.md, planner.md)
   Impact: prevents silent failures; forces pre-commitment to interpretation.
   ARIS is the only system that does this, and it is extremely valuable.
   Effort: add ~10 lines to plan template, ~10 to experiment_agent.md.

7. **Add LaTeX compilation checks** (reviewer.md or new utility)
   Impact: catches broken TeX before content review; prevents propagation of compilation errors.
   AI Scientist v1/v2 both have this and it catches real issues.
   Effort: add ~15 lines to reviewer.md.

8. **Add title and abstract writing guidance** (story_writer.md)
   Impact: title is most-read text; concrete guidance improves first impressions.
   AI Scientist v2 has explicit title tips; our template has none.
   Effort: add ~15 lines.

9. **Add novelty gate to planning** (planner.md)
   Impact: prevents wasted effort on already-published ideas.
   ARIS has a dedicated novelty-check skill.
   Effort: add ~10 lines.

10. **Add VLM figure review capability** (reviewer.md)
    Impact: catches figure-caption mismatches, unreadable plots, missing labels.
    AI Scientist v2 is the only system with this, and it is a genuine innovation.
    Effort: significant -- requires VLM integration, not just template changes.

11. **Add workflow DAG documentation** (new file)
    Impact: makes the multi-agent coordination explicit for dispatchers.
    Every competitor has some form of orchestration specification.
    Effort: create a ~30-line WORKFLOW.md.

12. **Add ensemble reviewer support** (reviewer.md)
    Impact: reduces single-reviewer bias; enables persona-based coverage.
    AI Scientist and Agent Laboratory both use ensembles.
    Effort: add ~15 lines to reviewer.md.
