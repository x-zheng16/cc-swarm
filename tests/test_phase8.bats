#!/usr/bin/env bats
# Phase 8 tests: File Locking + Activity Log

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    export TMUX="test"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$SWARM_DIR/dispatches" \
             "$SWARM_DIR/locks" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
    LOCK_LIB="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm_lock.sh"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- File Locking ---

@test "lock: acquire succeeds on fresh lock" {
    source "$LOCK_LIB"
    swarm_lock "$SWARM_DIR/locks/test1"
    [ -d "$SWARM_DIR/locks/test1" ]
    [ -f "$SWARM_DIR/locks/test1/pid" ]
    swarm_unlock "$SWARM_DIR/locks/test1"
}

@test "lock: acquire fails when lock held by live process" {
    source "$LOCK_LIB"
    swarm_lock "$SWARM_DIR/locks/test2"

    # Second acquire should fail
    run swarm_lock "$SWARM_DIR/locks/test2"
    [ "$status" -ne 0 ]

    swarm_unlock "$SWARM_DIR/locks/test2"
}

@test "lock: unlock removes lock dir" {
    source "$LOCK_LIB"
    swarm_lock "$SWARM_DIR/locks/test3"
    [ -d "$SWARM_DIR/locks/test3" ]

    swarm_unlock "$SWARM_DIR/locks/test3"
    [ ! -d "$SWARM_DIR/locks/test3" ]
}

@test "lock: stale lock from dead PID is reaped" {
    source "$LOCK_LIB"

    # Create a fake lock with a dead PID
    mkdir -p "$SWARM_DIR/locks/test4"
    echo "99999" > "$SWARM_DIR/locks/test4/pid"

    # Should succeed because old PID is dead
    swarm_lock "$SWARM_DIR/locks/test4"
    [ -d "$SWARM_DIR/locks/test4" ]

    local held_pid
    held_pid=$(cat "$SWARM_DIR/locks/test4/pid")
    [ "$held_pid" = "$$" ]

    swarm_unlock "$SWARM_DIR/locks/test4"
}

@test "lock: PID file contains current process PID" {
    source "$LOCK_LIB"
    swarm_lock "$SWARM_DIR/locks/test5"

    local held_pid
    held_pid=$(cat "$SWARM_DIR/locks/test5/pid")
    [ "$held_pid" = "$$" ]

    swarm_unlock "$SWARM_DIR/locks/test5"
}

@test "lock: with_lock executes command under lock" {
    source "$LOCK_LIB"

    with_lock "$SWARM_DIR/locks/test6" echo "hello" > /tmp/lock_test_$$
    [ "$(cat /tmp/lock_test_$$)" = "hello" ]

    # Lock should be released after
    [ ! -d "$SWARM_DIR/locks/test6" ]
    rm -f /tmp/lock_test_$$
}

# --- Activity Log ---

@test "log: swarm log shows empty message when no activity" {
    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"No activity"* ]]
}

@test "log: send action is logged" {
    "$SWARM_SCRIPT" send mbp:5.0 "Test message"

    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"send"* ]]
    [[ "$output" == *"mbp:5.0"* ]]
}

@test "log: ask action is logged" {
    "$SWARM_SCRIPT" ask mbp:5.0 "A question"

    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"ask"* ]]
}

@test "log: reply action is logged" {
    "$SWARM_SCRIPT" ask mbp:5.0 "For reply log test"

    local qa_file
    qa_file=$(ls "$SWARM_DIR/qa"/qa_*.json | head -1)
    local qa_id
    qa_id=$(jq -r '.qa_id' "$qa_file")

    "$SWARM_SCRIPT" reply "$qa_id" "The answer"

    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"reply"* ]]
}

@test "log: task create is logged" {
    "$SWARM_SCRIPT" task create --id 20260330_log_test --from mbp:1.0 --to mbp:5.0 \
        --prompt "Test task"

    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"task_create"* ]]
    [[ "$output" == *"20260330_log_test"* ]]
}

@test "log: drain action is logged" {
    "$SWARM_SCRIPT" drain mbp:5.0

    run "$SWARM_SCRIPT" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"drain"* ]]
}

@test "log: --last N limits output" {
    "$SWARM_SCRIPT" send mbp:5.0 "msg1"
    "$SWARM_SCRIPT" send mbp:5.0 "msg2"
    "$SWARM_SCRIPT" send mbp:5.0 "msg3"

    run "$SWARM_SCRIPT" log --last 2
    [ "$status" -eq 0 ]
    # Should show at most 2 entries (the last 2 sends)
    local count
    count=$(echo "$output" | grep -c '"send"' || true)
    [ "$count" -le 2 ]
}

@test "log: activity.jsonl file exists after action" {
    "$SWARM_SCRIPT" send mbp:5.0 "Test"

    [ -f "$SWARM_DIR/activity.jsonl" ]
    local lines
    lines=$(wc -l < "$SWARM_DIR/activity.jsonl" | tr -d ' ')
    [ "$lines" -ge 1 ]
}
