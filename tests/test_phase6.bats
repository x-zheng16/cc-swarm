#!/usr/bin/env bats
# Phase 6 tests: QA Protocol + Mailbox

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    export TMUX="test"  # Fake TMUX env so sender detection works
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$SWARM_DIR/dispatches" \
             "$SWARM_DIR/mailbox" "$SWARM_DIR/qa" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- swarm send ---

@test "send: creates inbox file with message" {
    "$SWARM_SCRIPT" send mbp:5.0 "Results ready at /tmp/output.json"

    local inbox_file="$SWARM_DIR/mailbox/mbp_5_0.jsonl"
    [ -f "$inbox_file" ]
    [ "$(wc -l < "$inbox_file" | tr -d ' ')" = "1" ]
    [[ "$(jq -r '.message' "$inbox_file")" == *"Results ready"* ]]
}

@test "send: multiple messages append to same inbox" {
    "$SWARM_SCRIPT" send mbp:5.0 "First message"
    "$SWARM_SCRIPT" send mbp:5.0 "Second message"

    local inbox_file="$SWARM_DIR/mailbox/mbp_5_0.jsonl"
    [ "$(wc -l < "$inbox_file" | tr -d ' ')" = "2" ]
}

@test "send: records sender and timestamp" {
    "$SWARM_SCRIPT" send mbp:5.0 "Hello"

    local inbox_file="$SWARM_DIR/mailbox/mbp_5_0.jsonl"
    local ts
    ts=$(jq -r '.timestamp' "$inbox_file")
    [ -n "$ts" ]
    [ "$ts" != "null" ]
}

@test "send: fails with no message" {
    run "$SWARM_SCRIPT" send mbp:5.0
    [ "$status" -ne 0 ]
}

# --- swarm inbox ---

@test "inbox: reads and clears messages" {
    "$SWARM_SCRIPT" send mbp:5.0 "Test message"

    # Read inbox for mbp:5.0
    run "$SWARM_SCRIPT" inbox --target mbp:5.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test message"* ]]
    [[ "$output" == *"inbox cleared"* ]]

    # Inbox should be empty now
    run "$SWARM_SCRIPT" inbox --target mbp:5.0
    [[ "$output" == *"No messages"* ]]
}

@test "inbox: --peek does not clear messages" {
    "$SWARM_SCRIPT" send mbp:5.0 "Peek message"

    # Peek
    run "$SWARM_SCRIPT" inbox --target mbp:5.0 --peek
    [ "$status" -eq 0 ]
    [[ "$output" == *"Peek message"* ]]
    [[ "$output" != *"inbox cleared"* ]]

    # Should still have messages
    run "$SWARM_SCRIPT" inbox --target mbp:5.0
    [[ "$output" == *"Peek message"* ]]
}

@test "inbox: shows empty message when no mail" {
    run "$SWARM_SCRIPT" inbox --target mbp:99.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"No messages"* ]]
}

# --- swarm ask ---

@test "ask: creates QA record file" {
    run "$SWARM_SCRIPT" ask mbp:planner.0 "Should we use black-box threat model?"
    [ "$status" -eq 0 ]

    # Should have created a qa_ file
    local qa_count
    qa_count=$(ls "$SWARM_DIR/qa"/qa_*.json 2>/dev/null | wc -l | tr -d ' ')
    [ "$qa_count" = "1" ]

    # Verify structure
    local qa_file
    qa_file=$(ls "$SWARM_DIR/qa"/qa_*.json | head -1)
    [ "$(jq -r '.status' "$qa_file")" = "pending" ]
    [[ "$(jq -r '.question' "$qa_file")" == *"black-box"* ]]
    [ "$(jq -r '.to' "$qa_file")" = "mbp:planner.0" ]
}

@test "ask: notifies target via inbox" {
    "$SWARM_SCRIPT" ask mbp:planner.0 "What is the scope?"

    local inbox_file="$SWARM_DIR/mailbox/mbp_planner_0.jsonl"
    [ -f "$inbox_file" ]
    [[ "$(cat "$inbox_file")" == *"[QA]"* ]]
    [[ "$(cat "$inbox_file")" == *"swarm reply"* ]]
}

@test "ask: fails with missing args" {
    run "$SWARM_SCRIPT" ask mbp:planner.0
    [ "$status" -ne 0 ]

    run "$SWARM_SCRIPT" ask
    [ "$status" -ne 0 ]
}

# --- swarm reply ---

@test "reply: updates QA record to answered" {
    "$SWARM_SCRIPT" ask mbp:planner.0 "Is black-box enough?"

    local qa_file
    qa_file=$(ls "$SWARM_DIR/qa"/qa_*.json | head -1)
    local qa_id
    qa_id=$(jq -r '.qa_id' "$qa_file")

    "$SWARM_SCRIPT" reply "$qa_id" "Yes, black-box only"

    [ "$(jq -r '.status' "$qa_file")" = "answered" ]
    [[ "$(jq -r '.answer' "$qa_file")" == *"black-box only"* ]]
    [ "$(jq -r '.answered_at' "$qa_file")" != "null" ]
}

@test "reply: notifies asker via inbox" {
    "$SWARM_SCRIPT" ask mbp:planner.0 "Question for reply test"

    local qa_file
    qa_file=$(ls "$SWARM_DIR/qa"/qa_*.json | head -1)
    local qa_id
    qa_id=$(jq -r '.qa_id' "$qa_file")
    local asker
    asker=$(jq -r '.from' "$qa_file")

    "$SWARM_SCRIPT" reply "$qa_id" "The answer"

    # Asker's inbox should have the reply
    local safe_asker
    safe_asker=$(echo "$asker" | tr ':.' '_')
    local inbox_file="$SWARM_DIR/mailbox/${safe_asker}.jsonl"
    [ -f "$inbox_file" ]
    [[ "$(cat "$inbox_file")" == *"[QA-REPLY]"* ]]
}

@test "reply: fails for nonexistent QA ID" {
    run "$SWARM_SCRIPT" reply qa_nonexistent_abc123 "Some answer"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- swarm qa ---

@test "qa: lists all QA records" {
    "$SWARM_SCRIPT" ask mbp:planner.0 "Question one"
    "$SWARM_SCRIPT" ask mbp:planner.0 "Question two"

    run "$SWARM_SCRIPT" qa
    [ "$status" -eq 0 ]
    [[ "$output" == *"Question one"* ]]
    [[ "$output" == *"Question two"* ]]
}

@test "qa: filters by state" {
    "$SWARM_SCRIPT" ask mbp:planner.0 "Pending question"
    "$SWARM_SCRIPT" ask mbp:planner.0 "Will be answered"

    # Answer the "Will be answered" one (find by content, not index)
    local qa_id
    for f in "$SWARM_DIR/qa"/qa_*.json; do
        if [[ "$(jq -r '.question' "$f")" == *"Will be answered"* ]]; then
            qa_id=$(jq -r '.qa_id' "$f")
            break
        fi
    done
    "$SWARM_SCRIPT" reply "$qa_id" "Done"

    # Filter pending only
    run "$SWARM_SCRIPT" qa --state pending
    [[ "$output" == *"Pending question"* ]]
    [[ "$output" != *"Will be answered"* ]]

    # Filter answered only
    run "$SWARM_SCRIPT" qa --state answered
    [[ "$output" == *"Will be answered"* ]]
    [[ "$output" != *"Pending question"* ]]
}

@test "qa: shows empty message when no records" {
    run "$SWARM_SCRIPT" qa
    [ "$status" -eq 0 ]
    [[ "$output" == *"No QA records"* ]]
}
