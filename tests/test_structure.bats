#!/usr/bin/env bats
# Structural tests: cc-swarm must contain ONLY infrastructure files

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# --- Infra files MUST exist ---

@test "structure: scripts/swarm exists and is executable" {
    [ -x "$REPO_ROOT/scripts/swarm" ]
}

@test "structure: scripts/swarm_dag.py exists" {
    [ -f "$REPO_ROOT/scripts/swarm_dag.py" ]
}

@test "structure: hooks/hooks.json exists" {
    [ -f "$REPO_ROOT/hooks/hooks.json" ]
}

@test "structure: hooks/register-agent.sh exists and is executable" {
    [ -x "$REPO_ROOT/hooks/register-agent.sh" ]
}

@test "structure: skills/swarm/SKILL.md exists" {
    [ -f "$REPO_ROOT/skills/swarm/SKILL.md" ]
}

@test "structure: .claude-plugin/plugin.json exists" {
    [ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]
}

@test "structure: agents/monitor.md exists (infra)" {
    [ -f "$REPO_ROOT/agents/monitor.md" ]
}

@test "structure: all test phases exist" {
    [ -f "$REPO_ROOT/tests/test_phase1.bats" ]
    [ -f "$REPO_ROOT/tests/test_phase2.bats" ]
    [ -f "$REPO_ROOT/tests/test_phase3.bats" ]
    [ -f "$REPO_ROOT/tests/test_phase4.bats" ]
    [ -f "$REPO_ROOT/tests/test_phase5.bats" ]
    [ -f "$REPO_ROOT/tests/test_phase6.bats" ]
}

# --- Domain files MUST NOT exist ---

@test "structure: no 0.1.0/ snapshot directory" {
    [ ! -d "$REPO_ROOT/0.1.0" ]
}

@test "structure: no templates/ directory" {
    [ ! -d "$REPO_ROOT/templates" ]
}

@test "structure: no taste_bundle/ directory" {
    [ ! -d "$REPO_ROOT/taste_bundle" ]
}

@test "structure: no docs/specs/ directory" {
    [ ! -d "$REPO_ROOT/docs/specs" ]
}

@test "structure: no AUDIT_REPORT.md at root" {
    [ ! -f "$REPO_ROOT/AUDIT_REPORT.md" ]
}

@test "structure: agents/ contains only infra agents" {
    local count
    count=$(ls "$REPO_ROOT/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
    # Only monitor.md and session-renamer.md
    [ "$count" -le 2 ]

    # No research agents
    [ ! -f "$REPO_ROOT/agents/planner.md" ]
    [ ! -f "$REPO_ROOT/agents/reviewer.md" ]
    [ ! -f "$REPO_ROOT/agents/method_writer.md" ]
    [ ! -f "$REPO_ROOT/agents/experiment_agent.md" ]
    [ ! -f "$REPO_ROOT/agents/survey_agent.md" ]
    [ ! -f "$REPO_ROOT/agents/story_writer.md" ]
}

# --- Hooks directory is minimal ---

@test "structure: hooks/ has exactly 2 files" {
    local count
    count=$(ls "$REPO_ROOT/hooks/" | wc -l | tr -d ' ')
    [ "$count" = "2" ]
}
