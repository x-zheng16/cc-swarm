#!/usr/bin/env bats
# Tests for swarm task update

setup() {
    export SWARM_DIR="$BATS_TMPDIR/test_swarm_$$"
    export AGENTS_DIR="$SWARM_DIR/agents"
    export TASKS_DIR="$SWARM_DIR/tasks"
    mkdir -p "$AGENTS_DIR" "$TASKS_DIR"

    # Resolve swarm script path
    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR"
}

# Helper: create a task with known state
create_test_task() {
    local task_id="$1"
    local state="${2:-created}"
    mkdir -p "$TASKS_DIR/$task_id"
    cat > "$TASKS_DIR/$task_id/envelope.json" << EOF
{"version":2,"task_id":"$task_id","from":"mbp:lead.0","to":"mbp:worker.0","type":"task","sent_at":"2026-03-31T00:00:00Z","result_path":"$TASKS_DIR/$task_id/result.md"}
EOF
    cat > "$TASKS_DIR/$task_id/status.json" << EOF
{"task_id":"$task_id","state":"$state","created_at":"2026-03-31T00:00:00Z","transitions":[{"from":"init","to":"$state","at":"2026-03-31T00:00:00Z"}]}
EOF
}

@test "task update: changes state in status.json" {
    create_test_task "test_update_1" "dispatched"

    run "$SWARM_SCRIPT" task update test_update_1 --state completed
    [ "$status" -eq 0 ]

    local new_state
    new_state=$(jq -r '.state' "$TASKS_DIR/test_update_1/status.json")
    [ "$new_state" = "completed" ]
}

@test "task update: appends transition record" {
    create_test_task "test_update_2" "dispatched"

    "$SWARM_SCRIPT" task update test_update_2 --state completed

    local count from to
    count=$(jq '.transitions | length' "$TASKS_DIR/test_update_2/status.json")
    [ "$count" -eq 2 ]

    from=$(jq -r '.transitions[1].from' "$TASKS_DIR/test_update_2/status.json")
    to=$(jq -r '.transitions[1].to' "$TASKS_DIR/test_update_2/status.json")
    [ "$from" = "dispatched" ]
    [ "$to" = "completed" ]
}

@test "task update: transition record has timestamp" {
    create_test_task "test_update_3" "dispatched"

    "$SWARM_SCRIPT" task update test_update_3 --state completed

    local at
    at=$(jq -r '.transitions[1].at' "$TASKS_DIR/test_update_3/status.json")
    # Should be an ISO timestamp, not null or empty
    [[ "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "task update: fails if task does not exist" {
    run "$SWARM_SCRIPT" task update nonexistent_task --state completed
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "task update: fails if --state is missing" {
    create_test_task "test_update_4" "dispatched"

    run "$SWARM_SCRIPT" task update test_update_4
    [ "$status" -ne 0 ]
    [[ "$output" == *"--state"* ]]
}

@test "task update: fails if task_id is missing" {
    run "$SWARM_SCRIPT" task update --state completed
    [ "$status" -ne 0 ]
    [[ "$output" == *"task"* ]]
}

@test "task update: multiple updates chain transitions" {
    create_test_task "test_update_5" "created"

    "$SWARM_SCRIPT" task update test_update_5 --state dispatched
    "$SWARM_SCRIPT" task update test_update_5 --state completed

    local count final_state
    count=$(jq '.transitions | length' "$TASKS_DIR/test_update_5/status.json")
    [ "$count" -eq 3 ]

    final_state=$(jq -r '.state' "$TASKS_DIR/test_update_5/status.json")
    [ "$final_state" = "completed" ]
}

@test "task update: prints confirmation message" {
    create_test_task "test_update_6" "dispatched"

    run "$SWARM_SCRIPT" task update test_update_6 --state completed
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_update_6"* ]]
    [[ "$output" == *"completed"* ]]
}

@test "task update: --state with no value fails cleanly" {
    create_test_task "test_update_7" "dispatched"

    run "$SWARM_SCRIPT" task update test_update_7 --state
    [ "$status" -ne 0 ]
    [[ "$output" == *"--state"* ]]
}

@test "task update: rejects task_id with path separators" {
    run "$SWARM_SCRIPT" task update "../../etc/passwd" --state completed
    [ "$status" -ne 0 ]
    [[ "$output" == *"path separator"* ]]
}

@test "task update: fails when status.json is missing" {
    mkdir -p "$TASKS_DIR/broken_task"

    run "$SWARM_SCRIPT" task update broken_task --state completed
    [ "$status" -ne 0 ]
    [[ "$output" == *"status.json"* ]]
}
