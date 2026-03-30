#!/usr/bin/env bats
# Tests for swarm triage: review result -> Linear tickets

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"

    # Create a mock linear CLI that logs calls
    export LINEAR_LOG="$BATS_TMPDIR/linear_calls_$$"
    export MOCK_LINEAR="$BATS_TMPDIR/mock_linear_$$"
    cat > "$MOCK_LINEAR" <<'MOCK'
#!/bin/bash
echo "$@" >> "$LINEAR_LOG"
echo "XZ-999"
MOCK
    chmod +x "$MOCK_LINEAR"

    # Create a sample review result with structured tables
    TASK_ID="test_triage_$$"
    TASK_DIR="$SWARM_DIR/tasks/$TASK_ID"
    mkdir -p "$TASK_DIR"

    cat > "$TASK_DIR/envelope.json" <<EOF
{"task_id": "$TASK_ID", "from": "mbp:reviewer.0", "to": "mbp:dev.0", "type": "review"}
EOF

    cat > "$TASK_DIR/status.json" <<EOF
{"state": "completed"}
EOF

    cat > "$TASK_DIR/result.md" <<'RESULT'
# Review: Test Feature

## Code Reviewer Findings

### Critical

| # | Confidence | Location | Issue |
| - | ---------- | -------- | ----- |
| CR-1 | 87% | `swarm:410-425` | **Dedup check TOCTOU race** -- status.json read-modify-write not protected by lock. |
| CR-2 | 90% | `swarm_lock.sh:47-51` | **with_lock leaks lock under set -e** -- needs trap guard. |

### Important

| # | Confidence | Location | Issue |
| - | ---------- | -------- | ----- |
| CR-3 | 95% | `swarm:474` | **date +%s%N broken on macOS** -- BSD date outputs literal N. |
| CR-4 | 85% | `swarm:302-328` | **--file after positional target parsed as prompt** -- silently wrong. |

### Minor

| # | Confidence | Location | Issue |
| - | ---------- | -------- | ----- |
| CR-5 | 70% | `swarm:100` | **Comment typo** -- says "v2" should say nothing. |
RESULT
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME" "$LINEAR_LOG" "$MOCK_LINEAR"
}

# --- dry-run: parses and displays issues ---

@test "triage: dry-run lists issues without creating tickets" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --dry-run --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CR-1"* ]]
    [[ "$output" == *"Critical"* ]]
    [[ "$output" == *"CR-3"* ]]
    [[ "$output" == *"Important"* ]]
    [[ "$output" == *"DRY RUN"* ]]
    # No linear calls should have been made
    [ ! -f "$LINEAR_LOG" ]
}

# --- parses all severity levels ---

@test "triage: parses critical, important, and minor issues" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --dry-run --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CR-1"* ]]
    [[ "$output" == *"CR-2"* ]]
    [[ "$output" == *"CR-3"* ]]
    [[ "$output" == *"CR-4"* ]]
    [[ "$output" == *"CR-5"* ]]
    [[ "$output" == *"5 issue(s)"* ]]
}

# --- creates Linear tickets ---

@test "triage: creates Linear tickets with correct priority" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [ -f "$LINEAR_LOG" ]

    # Critical -> priority 1
    grep -q -- "--priority 1" "$LINEAR_LOG"
    # Important -> priority 2
    grep -q -- "--priority 2" "$LINEAR_LOG"
    # Minor -> priority 3
    grep -q -- "--priority 3" "$LINEAR_LOG"
    # Should have 5 calls (5 issues)
    [ "$(wc -l < "$LINEAR_LOG")" -eq 5 ]
}

# --- min-severity filter ---

@test "triage: --min-severity important skips minor issues" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --min-severity important --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [ -f "$LINEAR_LOG" ]
    # Should have 4 calls (2 critical + 2 important, skip 1 minor)
    [ "$(wc -l < "$LINEAR_LOG")" -eq 4 ]
}

@test "triage: --min-severity critical skips important and minor" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --min-severity critical --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [ -f "$LINEAR_LOG" ]
    # Should have 2 calls (2 critical only)
    [ "$(wc -l < "$LINEAR_LOG")" -eq 2 ]
}

# --- error handling ---

@test "triage: fails when task_id not provided" {
    run "$SWARM_SCRIPT" triage
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "triage: fails when result.md doesn't exist" {
    rm "$SWARM_DIR/tasks/$TASK_ID/result.md"
    run "$SWARM_SCRIPT" triage "$TASK_ID" --linear-bin "$MOCK_LINEAR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"result.md"* ]]
}

@test "triage: fails when no structured tables found" {
    echo "# Plain text review with no tables" > "$SWARM_DIR/tasks/$TASK_ID/result.md"
    run "$SWARM_SCRIPT" triage "$TASK_ID" --linear-bin "$MOCK_LINEAR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No structured issues"* ]]
}

# --- logs to activity.jsonl ---

@test "triage: logs created tickets to activity.jsonl" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [ -f "$SWARM_DIR/activity.jsonl" ]
    grep -q "triage" "$SWARM_DIR/activity.jsonl"
    grep -q "$TASK_ID" "$SWARM_DIR/activity.jsonl"
}

# --- output summary ---

@test "triage: prints summary of created tickets" {
    run "$SWARM_SCRIPT" triage "$TASK_ID" --linear-bin "$MOCK_LINEAR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"XZ-"* ]]
    [[ "$output" == *"Created 5"* ]]
}
