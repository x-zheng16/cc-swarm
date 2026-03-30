#!/usr/bin/env bats
# Tests for swarm rename: atomic 3-layer name update

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- argument validation ---

@test "rename: fails when no name provided" {
    run "$SWARM_SCRIPT" rename
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

# --- strips prefix for window name ---

@test "rename: extracts window name by stripping prefix" {
    # swarm rename "[dev] my-feature" should produce window_name="my-feature"
    # We can't test tmux commands without tmux, but we can test the name parsing
    # by running with TMUX unset — it should fail gracefully
    unset TMUX
    run "$SWARM_SCRIPT" rename "[dev] my-feature"
    [ "$status" -ne 0 ]
    [[ "$output" == *"tmux"* ]]
}

# --- updates agent card if it exists ---

@test "rename: updates agent card pane field when card exists" {
    # Create a card with old name
    cat > "$SWARM_DIR/agents/mbp_old-name_0.json" <<'EOF'
{"pane": "mbp:old-name.0", "status": "idle", "role": "worker"}
EOF

    # swarm rename --update-card can be tested without tmux for the card logic
    # The command needs tmux for the actual rename, so we test the card update path
    # by calling with --card-only (internal flag for testing)
    run "$SWARM_SCRIPT" rename "[dev] new-name" \
        --old-pane "mbp:old-name.0" --card-only
    [ "$status" -eq 0 ]

    # Old card should be gone, new card should exist
    [ ! -f "$SWARM_DIR/agents/mbp_old-name_0.json" ]
    [ -f "$SWARM_DIR/agents/mbp_new-name_0.json" ]
    [ "$(jq -r '.pane' "$SWARM_DIR/agents/mbp_new-name_0.json")" = "mbp:new-name.0" ]
    # Preserved fields
    [ "$(jq -r '.role' "$SWARM_DIR/agents/mbp_new-name_0.json")" = "worker" ]
}

# --- handles name without prefix ---

@test "rename: name without prefix uses full name as window name" {
    cat > "$SWARM_DIR/agents/mbp_old_0.json" <<'EOF'
{"pane": "mbp:old.0", "status": "idle"}
EOF

    run "$SWARM_SCRIPT" rename "simple-name" \
        --old-pane "mbp:old.0" --card-only
    [ "$status" -eq 0 ]
    [ -f "$SWARM_DIR/agents/mbp_simple-name_0.json" ]
    [ "$(jq -r '.pane' "$SWARM_DIR/agents/mbp_simple-name_0.json")" = "mbp:simple-name.0" ]
}

# --- idempotent: renaming to same name ---

@test "rename: renaming to same name is idempotent" {
    cat > "$SWARM_DIR/agents/mbp_my-task_0.json" <<'EOF'
{"pane": "mbp:my-task.0", "status": "busy", "role": "lead"}
EOF

    run "$SWARM_SCRIPT" rename "[dev] my-task" \
        --old-pane "mbp:my-task.0" --card-only
    [ "$status" -eq 0 ]
    [ -f "$SWARM_DIR/agents/mbp_my-task_0.json" ]
    [ "$(jq -r '.role' "$SWARM_DIR/agents/mbp_my-task_0.json")" = "lead" ]
}
