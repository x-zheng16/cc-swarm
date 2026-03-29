#!/usr/bin/env bash
# Setup a research project from the DAG template.
# Usage: setup_project.sh <project_id> [paper_topic]
#
# Creates:
#   ~/.claude-swarm/tasks/<project_id>/
#     dag.json          -- instantiated DAG
#     prompts/          -- instantiated prompt files
#     research_contract.md  -- empty contract for user to fill
#     qa_log.md         -- empty QA log

set -euo pipefail

PROJECT_ID="${1:?Usage: setup_project.sh <project_id> [paper_topic]}"
PAPER_TOPIC="${2:-$PROJECT_ID}"
TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_DIR="$HOME/.claude-swarm/tasks/$PROJECT_ID"
PAPER_DIR="$HOME/projects/research/$PROJECT_ID/paper/drafts"

if [[ -d "$TASK_DIR" ]]; then
    echo "Error: $TASK_DIR already exists" >&2
    exit 1
fi

# Create directories
mkdir -p "$TASK_DIR/prompts"
mkdir -p "$PAPER_DIR"

# Instantiate DAG
sed -e "s|{PROJECT_ID}|$PROJECT_ID|g" \
    -e "s|{TASK_DIR}|$TASK_DIR|g" \
    -e "s|{PAPER_DIR}|$PAPER_DIR|g" \
    "$TEMPLATE_DIR/research_team_dag.json" > "$TASK_DIR/dag.json"

# Instantiate prompts
for f in "$TEMPLATE_DIR/prompts/"*.md; do
    name="$(basename "$f")"
    sed -e "s|{PROJECT_ID}|$PROJECT_ID|g" \
        -e "s|{TASK_DIR}|$TASK_DIR|g" \
        -e "s|{PAPER_DIR}|$PAPER_DIR|g" \
        -e "s|{PLANNER}|mbp:planner.0|g" \
        -e "s|{STORY_WRITER}|mbp:story-writer.0|g" \
        -e "s|{SURVEY_AGENT}|mbp:survey-agent.0|g" \
        -e "s|{METHOD_WRITER}|mbp:method-writer.0|g" \
        -e "s|{EXPERIMENT_AGENT}|mbp:experiment-agent.0|g" \
        -e "s|{REVIEWER}|mbp:reviewer.0|g" \
        "$f" > "$TASK_DIR/prompts/$name"
done

# Create research contract template
cat > "$TASK_DIR/research_contract.md" << 'TMPL'
# Research Contract

## Paper Topic
{PAPER_TOPIC}

## Target Venue
{venue, e.g., NeurIPS 2026}

## Core Idea
{1-2 paragraphs: what we propose and why it matters}

## Threat Model / Assumptions
{Who is the adversary? What can they do? What is the goal?}

## Scope Constraints
- Page limit: {e.g., 9 pages body + unlimited appendix}
- Compute budget: {e.g., 4x A100 for 2 weeks}
- Deadline: {date}

## Key Differentiator
{What makes this different from existing work?}

## Non-Goals
{What this paper is NOT about}
TMPL

sed -i '' "s|{PAPER_TOPIC}|$PAPER_TOPIC|g" "$TASK_DIR/research_contract.md"

# Initialize empty QA log
cat > "$TASK_DIR/qa_log.md" << 'EOF'
# QA Log

Inter-agent QA interactions for this project.
Format: see ~/cc-plugins/cc-swarm/docs/specs/qa_protocol.md
EOF

echo "Project setup complete:"
echo "  Task dir:  $TASK_DIR"
echo "  Paper dir: $PAPER_DIR"
echo "  DAG:       $TASK_DIR/dag.json"
echo ""
echo "Next steps:"
echo "  1. Edit $TASK_DIR/research_contract.md"
echo "  2. Launch agents: swarm launch mbp --count 6"
echo "  3. Run DAG: swarm run $TASK_DIR/dag.json"
