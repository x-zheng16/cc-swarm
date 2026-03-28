#!/usr/bin/env bats
# Phase 2 tests: V2 Dispatch Protocol (--task flag)

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$SWARM_DIR/dispatches" "$SWARM_DIR/mailbox" "$HOME"

    # Resolve swarm script path
    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# Helper: create a task with prompt.md for dispatch tests
create_test_task() {
    local task_id="$1"
    local to="${2:-mbp:5.0}"
    "$SWARM_SCRIPT" task create --id "$task_id" --from mbp:1.0 --to "$to" \
        --prompt "Execute the test task"
}

# Helper: create an agent card for the target
create_agent_card() {
    local target="$1"
    local safe_name
    safe_name=$(echo "$target" | tr ':.' '_')
    cat > "$SWARM_DIR/agents/${safe_name}.json" <<EOF
{
  "pane": "$target",
  "status": "idle",
  "session_id": "test-session-id",
  "cwd": "/tmp"
}
EOF
}

# --- dispatch --task: updates status.json to "dispatched" ---

@test "dispatch --task: updates status.json to dispatched" {
    create_test_task "20260328_dispatch_test"
    create_agent_card "mbp:5.0"

    # Run dispatch --task (tmux won't be available, so it should update files then fail/skip tmux)
    run "$SWARM_SCRIPT" dispatch --task 20260328_dispatch_test
    # We don't check exit code because tmux will fail in test env

    # Verify status.json was updated
    local state
    state=$(jq -r '.state' "$SWARM_DIR/tasks/20260328_dispatch_test/status.json")
    [ "$state" = "dispatched" ]

    # Verify dispatched_at was set
    local dispatched_at
    dispatched_at=$(jq -r '.dispatched_at' "$SWARM_DIR/tasks/20260328_dispatch_test/status.json")
    [ "$dispatched_at" != "null" ]
    [ -n "$dispatched_at" ]

    # Verify transition was added
    local last_transition_to
    last_transition_to=$(jq -r '.transitions[-1].to' "$SWARM_DIR/tasks/20260328_dispatch_test/status.json")
    [ "$last_transition_to" = "dispatched" ]
}

# --- dispatch --task: fails if task dir doesn't exist ---

@test "dispatch --task: fails if task dir does not exist" {
    run "$SWARM_SCRIPT" dispatch --task nonexistent_task_xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- dispatch --task: fails if prompt.md is missing ---

@test "dispatch --task: fails if prompt.md is missing" {
    # Create task WITHOUT --prompt so no prompt.md exists
    "$SWARM_SCRIPT" task create --id 20260328_no_prompt --from mbp:1.0 --to mbp:5.0

    run "$SWARM_SCRIPT" dispatch --task 20260328_no_prompt
    [ "$status" -ne 0 ]
    [[ "$output" == *"prompt.md"* ]]
}

# --- dispatch --task: fails if envelope.json is missing ---

@test "dispatch --task: fails if envelope.json is missing" {
    # Create the task dir manually without envelope.json
    mkdir -p "$SWARM_DIR/tasks/20260328_bad_task"
    echo "some prompt" > "$SWARM_DIR/tasks/20260328_bad_task/prompt.md"

    run "$SWARM_SCRIPT" dispatch --task 20260328_bad_task
    [ "$status" -ne 0 ]
    [[ "$output" == *"envelope.json"* ]]
}

# --- dispatch --task: sets agent card current_task ---

@test "dispatch --task: sets agent card current_task" {
    create_test_task "20260328_card_update"
    create_agent_card "mbp:5.0"

    run "$SWARM_SCRIPT" dispatch --task 20260328_card_update

    local current_task
    current_task=$(jq -r '.current_task' "$SWARM_DIR/agents/mbp_5_0.json")
    [ "$current_task" = "20260328_card_update" ]
}

# --- dispatch --task: validates required envelope fields ---

@test "dispatch --task: validates envelope required fields" {
    # Create a task dir with an envelope missing the 'to' field
    mkdir -p "$SWARM_DIR/tasks/20260328_bad_envelope"
    echo '{"task_id": "20260328_bad_envelope", "from": "mbp:1.0"}' > "$SWARM_DIR/tasks/20260328_bad_envelope/envelope.json"
    echo '{"state": "created"}' > "$SWARM_DIR/tasks/20260328_bad_envelope/status.json"
    echo "prompt" > "$SWARM_DIR/tasks/20260328_bad_envelope/prompt.md"

    run "$SWARM_SCRIPT" dispatch --task 20260328_bad_envelope
    [ "$status" -ne 0 ]
    [[ "$output" == *"to"* ]]
}

# --- dispatch --task: reads target from envelope.json 'to' field ---

@test "dispatch --task: reads dispatch target from envelope 'to' field" {
    # Create task targeting mbp:7.0
    "$SWARM_SCRIPT" task create --id 20260328_target_test --from mbp:1.0 --to mbp:7.0 \
        --prompt "Do the thing"
    create_agent_card "mbp:7.0"

    run "$SWARM_SCRIPT" dispatch --task 20260328_target_test

    # Agent card for mbp:7.0 (not mbp:5.0) should have current_task set
    local current_task
    current_task=$(jq -r '.current_task' "$SWARM_DIR/agents/mbp_7_0.json")
    [ "$current_task" = "20260328_target_test" ]
}

# --- regular dispatch (no --task) still works ---

@test "dispatch without --task: backward compatible (fails on tmux, not on args)" {
    # Without --task, dispatch requires target + prompt as positional args.
    # In test env, it will fail on tmux validation, NOT on task validation.
    run "$SWARM_SCRIPT" dispatch mbp:5.0 "Hello world"

    # Should fail because tmux session doesn't exist (expected in test env)
    [ "$status" -ne 0 ]
    # Error should be about tmux, NOT about task
    [[ "$output" == *"tmux"* ]] || [[ "$output" == *"session"* ]]
    [[ "$output" != *"task"* ]]
}

# --- dispatch --task: status transitions are correct ---

@test "dispatch --task: transition records from=created to=dispatched" {
    create_test_task "20260328_transition"
    create_agent_card "mbp:5.0"

    run "$SWARM_SCRIPT" dispatch --task 20260328_transition

    local from_state to_state
    from_state=$(jq -r '.transitions[-1].from' "$SWARM_DIR/tasks/20260328_transition/status.json")
    to_state=$(jq -r '.transitions[-1].to' "$SWARM_DIR/tasks/20260328_transition/status.json")

    [ "$from_state" = "created" ]
    [ "$to_state" = "dispatched" ]
}

# --- dispatch --task with --force flag ---

@test "dispatch --task: accepts --force flag" {
    create_test_task "20260328_force_test"
    create_agent_card "mbp:5.0"

    # --force should be recognized alongside --task
    run "$SWARM_SCRIPT" dispatch --task 20260328_force_test --force

    local state
    state=$(jq -r '.state' "$SWARM_DIR/tasks/20260328_force_test/status.json")
    [ "$state" = "dispatched" ]
}
