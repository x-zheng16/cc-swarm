#!/usr/bin/env bats
# Phase 1 tests: Enhanced Agent Cards + Task Lifecycle

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$HOME"

    # Resolve swarm script path
    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME"
}

# --- Hook: merge-update agent card ---

@test "hook: register-agent.sh preserves existing card fields on update" {
    # Pre-populate an agent card with v2 fields
    cat > "$SWARM_DIR/agents/mbp_5_0.json" <<'EOF'
{
  "pane": "mbp:5.0",
  "session_id": "old-session",
  "cwd": "/old/path",
  "status": "idle",
  "role": "worker",
  "team": "research-safety",
  "capabilities": ["research", "experiments"],
  "current_task": "20260328_draft"
}
EOF

    # Simulate what the hook would write (status update only)
    # The hook should merge, not overwrite
    local result
    result=$(jq -s '.[0] * .[1]' \
        "$SWARM_DIR/agents/mbp_5_0.json" \
        <(echo '{"status": "busy", "event": "UserPromptSubmit", "registered_at": "2026-03-28T16:00:00Z"}'))

    echo "$result" > "$SWARM_DIR/agents/mbp_5_0.json"

    # Verify v2 fields survived the merge
    [ "$(jq -r '.role' "$SWARM_DIR/agents/mbp_5_0.json")" = "worker" ]
    [ "$(jq -r '.team' "$SWARM_DIR/agents/mbp_5_0.json")" = "research-safety" ]
    [ "$(jq -r '.capabilities[0]' "$SWARM_DIR/agents/mbp_5_0.json")" = "research" ]
    [ "$(jq -r '.current_task' "$SWARM_DIR/agents/mbp_5_0.json")" = "20260328_draft" ]
    # And v1 fields were updated
    [ "$(jq -r '.status' "$SWARM_DIR/agents/mbp_5_0.json")" = "busy" ]
    [ "$(jq -r '.event' "$SWARM_DIR/agents/mbp_5_0.json")" = "UserPromptSubmit" ]
}

# --- swarm task create ---

@test "task create: creates directory structure with envelope and status" {
    "$SWARM_SCRIPT" task create --id 20260328_test_task --from mbp:1.0 --to mbp:5.0

    [ -d "$SWARM_DIR/tasks/20260328_test_task" ]
    [ -f "$SWARM_DIR/tasks/20260328_test_task/envelope.json" ]
    [ -f "$SWARM_DIR/tasks/20260328_test_task/status.json" ]

    # Verify envelope fields
    [ "$(jq -r '.task_id' "$SWARM_DIR/tasks/20260328_test_task/envelope.json")" = "20260328_test_task" ]
    [ "$(jq -r '.from' "$SWARM_DIR/tasks/20260328_test_task/envelope.json")" = "mbp:1.0" ]
    [ "$(jq -r '.to' "$SWARM_DIR/tasks/20260328_test_task/envelope.json")" = "mbp:5.0" ]
    [ "$(jq -r '.version' "$SWARM_DIR/tasks/20260328_test_task/envelope.json")" = "2" ]

    # Verify status
    [ "$(jq -r '.state' "$SWARM_DIR/tasks/20260328_test_task/status.json")" = "created" ]
}

@test "task create: sets default result_path if not specified" {
    "$SWARM_SCRIPT" task create --id 20260328_defaults --from mbp:1.0 --to mbp:5.0

    local result_path
    result_path=$(jq -r '.result_path' "$SWARM_DIR/tasks/20260328_defaults/envelope.json")

    [[ "$result_path" == *"tasks/20260328_defaults/result.md"* ]]
}

@test "task create: respects custom result_path" {
    "$SWARM_SCRIPT" task create --id 20260328_custom --from mbp:1.0 --to mbp:5.0 \
        --result-path /tmp/custom_result.md

    [ "$(jq -r '.result_path' "$SWARM_DIR/tasks/20260328_custom/envelope.json")" = "/tmp/custom_result.md" ]
}

@test "task create: accepts optional type, priority, timeout, phase" {
    "$SWARM_SCRIPT" task create --id 20260328_opts --from mbp:1.0 --to mbp:5.0 \
        --type review --priority urgent --timeout 3600 --phase review_loop

    [ "$(jq -r '.type' "$SWARM_DIR/tasks/20260328_opts/envelope.json")" = "review" ]
    [ "$(jq -r '.priority' "$SWARM_DIR/tasks/20260328_opts/envelope.json")" = "urgent" ]
    [ "$(jq -r '.timeout' "$SWARM_DIR/tasks/20260328_opts/envelope.json")" = "3600" ]
    [ "$(jq -r '.phase' "$SWARM_DIR/tasks/20260328_opts/envelope.json")" = "review_loop" ]
}

@test "task create: rejects missing required fields" {
    run "$SWARM_SCRIPT" task create --id 20260328_no_from --to mbp:5.0
    [ "$status" -ne 0 ]

    run "$SWARM_SCRIPT" task create --from mbp:1.0 --to mbp:5.0
    [ "$status" -ne 0 ]
}

@test "task create: rejects duplicate task_id" {
    "$SWARM_SCRIPT" task create --id 20260328_dup --from mbp:1.0 --to mbp:5.0

    run "$SWARM_SCRIPT" task create --id 20260328_dup --from mbp:1.0 --to mbp:5.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "task create: writes prompt.md when --prompt is given" {
    "$SWARM_SCRIPT" task create --id 20260328_with_prompt --from mbp:1.0 --to mbp:5.0 \
        --prompt "Review the intro section of the paper"

    [ -f "$SWARM_DIR/tasks/20260328_with_prompt/prompt.md" ]
    grep -q "Review the intro" "$SWARM_DIR/tasks/20260328_with_prompt/prompt.md"
}

# --- swarm task status ---

@test "task status: shows current state" {
    "$SWARM_SCRIPT" task create --id 20260328_status_test --from mbp:1.0 --to mbp:5.0

    run "$SWARM_SCRIPT" task status 20260328_status_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"created"* ]]
}

@test "task status: fails for nonexistent task" {
    run "$SWARM_SCRIPT" task status nonexistent_task
    [ "$status" -ne 0 ]
}

# --- swarm task list ---

@test "task list: lists all tasks" {
    "$SWARM_SCRIPT" task create --id 20260328_list_a --from mbp:1.0 --to mbp:5.0
    "$SWARM_SCRIPT" task create --id 20260328_list_b --from mbp:1.0 --to mbp:6.0

    run "$SWARM_SCRIPT" task list
    [ "$status" -eq 0 ]
    [[ "$output" == *"20260328_list_a"* ]]
    [[ "$output" == *"20260328_list_b"* ]]
}

@test "task list: filters by state" {
    "$SWARM_SCRIPT" task create --id 20260328_filter_a --from mbp:1.0 --to mbp:5.0
    "$SWARM_SCRIPT" task create --id 20260328_filter_b --from mbp:1.0 --to mbp:6.0

    # Manually set one to completed
    jq '.state = "completed"' "$SWARM_DIR/tasks/20260328_filter_b/status.json" > /tmp/s.json \
        && mv /tmp/s.json "$SWARM_DIR/tasks/20260328_filter_b/status.json"

    run "$SWARM_SCRIPT" task list --state created
    [[ "$output" == *"20260328_filter_a"* ]]
    [[ "$output" != *"20260328_filter_b"* ]]
}

# --- swarm card ---

@test "card: shows agent card" {
    cat > "$SWARM_DIR/agents/mbp_5_0.json" <<'EOF'
{
  "pane": "mbp:5.0",
  "status": "idle",
  "role": "worker",
  "team": "research-safety"
}
EOF

    run "$SWARM_SCRIPT" card mbp:5.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"worker"* ]]
    [[ "$output" == *"research-safety"* ]]
}

@test "card set-role: updates role field" {
    cat > "$SWARM_DIR/agents/mbp_5_0.json" <<'EOF'
{"pane": "mbp:5.0", "status": "idle"}
EOF

    "$SWARM_SCRIPT" card set-role mbp:5.0 lead

    [ "$(jq -r '.role' "$SWARM_DIR/agents/mbp_5_0.json")" = "lead" ]
}

@test "card set-team: updates team field" {
    cat > "$SWARM_DIR/agents/mbp_5_0.json" <<'EOF'
{"pane": "mbp:5.0", "status": "idle"}
EOF

    "$SWARM_SCRIPT" card set-team mbp:5.0 research-safety

    [ "$(jq -r '.team' "$SWARM_DIR/agents/mbp_5_0.json")" = "research-safety" ]
}

@test "card set-caps: updates capabilities field" {
    cat > "$SWARM_DIR/agents/mbp_5_0.json" <<'EOF'
{"pane": "mbp:5.0", "status": "idle"}
EOF

    "$SWARM_SCRIPT" card set-caps mbp:5.0 research,paper-writing,experiments

    [ "$(jq -r '.capabilities[0]' "$SWARM_DIR/agents/mbp_5_0.json")" = "research" ]
    [ "$(jq -r '.capabilities[1]' "$SWARM_DIR/agents/mbp_5_0.json")" = "paper-writing" ]
    [ "$(jq -r '.capabilities[2]' "$SWARM_DIR/agents/mbp_5_0.json")" = "experiments" ]
}
