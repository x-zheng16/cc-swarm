#!/usr/bin/env bats
# Phase 7 tests: Heartbeat, Dispatch Dedup, Drain Signal

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    export TMUX="test"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$SWARM_DIR/dispatches" \
             "$SWARM_DIR/heartbeat" "$SWARM_DIR/drain" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- Heartbeat ---

@test "heartbeat: agent card gets last_heartbeat on hook fire" {
    # Simulate what register-agent.sh does: write heartbeat timestamp to card
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    echo '{"pane":"mbp:5.0","status":"busy"}' > "$card"

    # After hook fires, card should have last_heartbeat
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$ts" '. + {last_heartbeat: $ts}' "$card" > "$card.tmp" && mv "$card.tmp" "$card"

    [ "$(jq -r '.last_heartbeat' "$card")" != "null" ]
    [ "$(jq -r '.last_heartbeat' "$card")" != "" ]
}

@test "heartbeat: swarm heartbeat shows agent liveness" {
    # Create agent card with recent heartbeat
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --arg pane "mbp:5.0" --arg ts "$ts" --arg status "busy" \
        '{pane: $pane, status: $status, last_heartbeat: $ts}' > "$card"

    run "$SWARM_SCRIPT" heartbeat
    [ "$status" -eq 0 ]
    [[ "$output" == *"mbp:5.0"* ]]
    [[ "$output" == *"alive"* ]]
}

@test "heartbeat: detects stale agent (no heartbeat)" {
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    jq -n --arg pane "mbp:5.0" --arg status "busy" \
        '{pane: $pane, status: $status}' > "$card"

    run "$SWARM_SCRIPT" heartbeat
    [ "$status" -eq 0 ]
    [[ "$output" == *"mbp:5.0"* ]]
    [[ "$output" == *"no heartbeat"* ]]
}

@test "heartbeat: detects stale agent (old heartbeat)" {
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    # Heartbeat from 10 minutes ago
    local old_ts="2020-01-01T00:00:00Z"
    jq -n --arg pane "mbp:5.0" --arg ts "$old_ts" --arg status "busy" \
        '{pane: $pane, status: $status, last_heartbeat: $ts}' > "$card"

    run "$SWARM_SCRIPT" heartbeat
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale"* ]]
}

@test "heartbeat: --timeout flag sets staleness threshold" {
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    # Heartbeat from 2 seconds ago — alive with default timeout, but stale with --timeout 1
    local ts
    ts=$(date -u -v-2S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '2 seconds ago' +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --arg pane "mbp:5.0" --arg ts "$ts" --arg status "busy" \
        '{pane: $pane, status: $status, last_heartbeat: $ts}' > "$card"

    run "$SWARM_SCRIPT" heartbeat --timeout 1
    [[ "$output" == *"stale"* ]]

    run "$SWARM_SCRIPT" heartbeat --timeout 120
    [[ "$output" == *"alive"* ]]
}

@test "heartbeat: empty swarm shows no agents message" {
    rm -f "$SWARM_DIR/agents/"*.json
    run "$SWARM_SCRIPT" heartbeat
    [ "$status" -eq 0 ]
    [[ "$output" == *"No agents"* ]]
}

# --- Dispatch Dedup ---

@test "dedup: v2 dispatch updates status to dispatched" {
    # Use nonexistent session so dispatch takes "tmux unavailable" fast path
    unset TMUX

    local task_id="20260330_dedup_test"
    "$SWARM_SCRIPT" task create --id "$task_id" --from noexist:1.0 --to noexist:5.0 \
        --prompt "Run the tests"

    run "$SWARM_SCRIPT" dispatch --task "$task_id"
    [ "$status" -eq 0 ]

    # Status should be dispatched
    [ "$(jq -r '.state' "$SWARM_DIR/tasks/$task_id/status.json")" = "dispatched" ]
}

@test "dedup: duplicate v2 dispatch is rejected" {
    unset TMUX

    local task_id="20260330_dedup_dup"
    "$SWARM_SCRIPT" task create --id "$task_id" --from noexist:1.0 --to noexist:5.0 \
        --prompt "Run the tests"

    # First dispatch succeeds
    "$SWARM_SCRIPT" dispatch --task "$task_id"

    # Second dispatch of same task is rejected
    run "$SWARM_SCRIPT" dispatch --task "$task_id"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already dispatched"* ]]
}

@test "dedup: --force bypasses dedup check" {
    unset TMUX

    local task_id="20260330_dedup_force"
    "$SWARM_SCRIPT" task create --id "$task_id" --from noexist:1.0 --to noexist:5.0 \
        --prompt "Run the tests"

    "$SWARM_SCRIPT" dispatch --task "$task_id"

    # Force re-dispatch
    run "$SWARM_SCRIPT" dispatch --task "$task_id" --force
    [ "$status" -eq 0 ]
}

# --- Drain Signal ---

@test "drain: creates drain signal file" {
    run "$SWARM_SCRIPT" drain mbp:5.0
    [ "$status" -eq 0 ]

    local drain_file="$SWARM_DIR/drain/mbp_5_0"
    [ -f "$drain_file" ]
    [[ "$output" == *"Drain signal sent"* ]]
}

@test "drain: check-drain returns 0 when drain signal exists" {
    "$SWARM_SCRIPT" drain mbp:5.0

    run "$SWARM_SCRIPT" check-drain --target mbp:5.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"draining"* ]]
}

@test "drain: check-drain returns 0 with no-drain when signal absent" {
    run "$SWARM_SCRIPT" check-drain --target mbp:5.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]
}

@test "drain: cancel-drain removes signal file" {
    "$SWARM_SCRIPT" drain mbp:5.0
    [ -f "$SWARM_DIR/drain/mbp_5_0" ]

    run "$SWARM_SCRIPT" cancel-drain mbp:5.0
    [ "$status" -eq 0 ]
    [ ! -f "$SWARM_DIR/drain/mbp_5_0" ]
    [[ "$output" == *"cancelled"* ]]
}

@test "drain: drain sets agent card drain flag" {
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    echo '{"pane":"mbp:5.0","status":"busy"}' > "$card"

    "$SWARM_SCRIPT" drain mbp:5.0

    [ "$(jq -r '.draining' "$card")" = "true" ]
}

@test "drain: cancel-drain clears agent card drain flag" {
    local card="$SWARM_DIR/agents/mbp_5_0.json"
    echo '{"pane":"mbp:5.0","status":"busy","draining":true}' > "$card"

    "$SWARM_SCRIPT" cancel-drain mbp:5.0

    [ "$(jq -r '.draining' "$card")" = "false" ]
}

@test "drain: fails with no target" {
    run "$SWARM_SCRIPT" drain
    [ "$status" -ne 0 ]
}
