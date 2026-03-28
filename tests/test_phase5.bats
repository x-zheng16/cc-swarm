#!/usr/bin/env bats
# Phase 5 tests: Monitor Agent

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$SWARM_DIR/dispatches" "$SWARM_DIR/mailbox" "$HOME"

    # Resolve swarm script path
    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"

    # Resolve agents dir for template checks
    AGENTS_TEMPLATE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/agents"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- monitor.md template ---

@test "monitor.md: template file exists" {
    [ -f "$AGENTS_TEMPLATE_DIR/monitor.md" ]
}

@test "monitor.md: contains key section — Role" {
    grep -qi "role\|you are" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: contains key section — Detection" {
    grep -qi "detect\|detection" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: contains key section — Interventions" {
    grep -qi "intervention" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: contains key section — Escalation" {
    grep -qi "escalat" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: contains key section — Safety constraints" {
    grep -qi "never\|forbidden\|do not" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: references swarm status command" {
    grep -q "swarm status" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: references swarm send command" {
    grep -q "swarm send" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: references swarm monitor command" {
    grep -q "swarm monitor" "$AGENTS_TEMPLATE_DIR/monitor.md"
}

@test "monitor.md: is between 80 and 200 lines" {
    local lines
    lines=$(wc -l < "$AGENTS_TEMPLATE_DIR/monitor.md")
    [ "$lines" -ge 80 ]
    [ "$lines" -le 200 ]
}

# --- swarm monitor-start ---

@test "monitor-start: creates monitor directory" {
    run "$SWARM_SCRIPT" monitor-start --dry-run

    [ -d "$SWARM_DIR/monitor" ]
}

@test "monitor-start: creates initial status.txt" {
    run "$SWARM_SCRIPT" monitor-start --dry-run

    [ -f "$SWARM_DIR/monitor/status.txt" ]
    grep -q "swarm monitor" "$SWARM_DIR/monitor/status.txt"
}

@test "monitor-start: initial status.txt contains starting state" {
    run "$SWARM_SCRIPT" monitor-start --dry-run

    grep -q "starting" "$SWARM_DIR/monitor/status.txt"
}

@test "monitor-start: dry-run does not launch tmux" {
    run "$SWARM_SCRIPT" monitor-start --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"Dry run"* ]]
}

@test "monitor-start: without tmux fails gracefully" {
    # No --dry-run and no tmux session -> should fail with helpful error
    run "$SWARM_SCRIPT" monitor-start --session nonexistent_session_xyz
    [ "$status" -ne 0 ]
}

# --- swarm monitor-status ---

@test "monitor-status: reads and displays status.txt" {
    mkdir -p "$SWARM_DIR/monitor"
    echo "[2026-03-28 12:00] All agents healthy. 3 idle, 2 busy." > "$SWARM_DIR/monitor/status.txt"

    run "$SWARM_SCRIPT" monitor-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"All agents healthy"* ]]
}

@test "monitor-status: shows error when no status.txt exists" {
    # Ensure monitor dir does not exist
    rm -rf "$SWARM_DIR/monitor"

    run "$SWARM_SCRIPT" monitor-status
    [ "$status" -ne 0 ]
    [[ "$output" == *"not running"* ]] || [[ "$output" == *"No monitor"* ]]
}

@test "monitor-status: shows error when status.txt is empty" {
    mkdir -p "$SWARM_DIR/monitor"
    touch "$SWARM_DIR/monitor/status.txt"

    run "$SWARM_SCRIPT" monitor-status
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty"* ]] || [[ "$output" == *"not running"* ]] || [[ "$output" == *"No monitor"* ]]
}

# --- routing ---

@test "routing: monitor-start is recognized" {
    run "$SWARM_SCRIPT" monitor-start --dry-run
    [ "$status" -eq 0 ]
}

@test "routing: monitor-status is recognized" {
    mkdir -p "$SWARM_DIR/monitor"
    echo "ok" > "$SWARM_DIR/monitor/status.txt"

    run "$SWARM_SCRIPT" monitor-status
    [ "$status" -eq 0 ]
}

# --- help includes monitor commands ---

@test "help: mentions monitor-start" {
    run "$SWARM_SCRIPT" help
    [[ "$output" == *"monitor-start"* ]]
}

@test "help: mentions monitor-status" {
    run "$SWARM_SCRIPT" help
    [[ "$output" == *"monitor-status"* ]]
}
