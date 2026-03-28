#!/usr/bin/env bats
# Phase 4 tests: Review Exchange Protocol

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

# Helper: create a completed source task with a result file
create_source_task() {
    local task_id="$1"
    local from="${2:-mbp:1.0}"
    local to="${3:-mbp:5.0}"
    "$SWARM_SCRIPT" task create --id "$task_id" --from "$from" --to "$to" \
        --prompt "Execute the original task"
    # Simulate completion: write a result.md
    echo "# Draft Result" > "$SWARM_DIR/tasks/$task_id/result.md"
    echo "This is the task output." >> "$SWARM_DIR/tasks/$task_id/result.md"
}

# Helper: create an agent card for the reviewer
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

# --- review: creates review task directory with correct naming ---

@test "review: creates review task with _review_r1 suffix" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    run "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0
    [ "$status" -eq 0 ]

    # Review task directory should exist
    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r1" ]
}

# --- review: envelope has type=review ---

@test "review: envelope has type=review" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local review_type
    review_type=$(jq -r '.type' "$SWARM_DIR/tasks/20260328_draft_review_r1/envelope.json")
    [ "$review_type" = "review" ]
}

# --- review: auto-increments round number ---

@test "review: auto-increments round number (r1 exists -> creates r2)" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    # Create first review
    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r1" ]

    # Create second review
    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r2" ]
}

# --- review: fails if source task doesn't exist ---

@test "review: fails if source task does not exist" {
    run "$SWARM_SCRIPT" review nonexistent_task --reviewer mbp:reviewer.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- review: generates prompt.md with review format ---

@test "review: generates prompt.md with review format instructions" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local prompt_file="$SWARM_DIR/tasks/20260328_draft_review_r1/prompt.md"
    [ -f "$prompt_file" ]

    # Must contain the review format sections
    run cat "$prompt_file"
    [[ "$output" == *"Verdict"* ]]
    [[ "$output" == *"Critical Issues"* ]]
    [[ "$output" == *"Important Issues"* ]]
    [[ "$output" == *"Minor Issues"* ]]
    [[ "$output" == *"Strengths"* ]]
    [[ "$output" == *"Summary"* ]]
}

# --- review: with --artifact uses custom artifact path ---

@test "review: --artifact uses custom artifact path in prompt" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0 \
        --artifact /Users/x/projects/research/paper/main.tex

    local prompt_file="$SWARM_DIR/tasks/20260328_draft_review_r1/prompt.md"
    run cat "$prompt_file"
    [[ "$output" == *"/Users/x/projects/research/paper/main.tex"* ]]
}

# --- review: sets from/to correctly (author -> reviewer) ---

@test "review: from=original author, to=reviewer" {
    # Source task: from=mbp:1.0, to=mbp:5.0 (so author is mbp:5.0)
    create_source_task "20260328_draft" "mbp:1.0" "mbp:5.0"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local env_file="$SWARM_DIR/tasks/20260328_draft_review_r1/envelope.json"
    [ "$(jq -r '.from' "$env_file")" = "mbp:5.0" ]
    [ "$(jq -r '.to' "$env_file")" = "mbp:reviewer.0" ]
}

# --- review: envelope has correct result_path ---

@test "review: envelope result_path points to review.md" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local result_path
    result_path=$(jq -r '.result_path' "$SWARM_DIR/tasks/20260328_draft_review_r1/envelope.json")
    [[ "$result_path" == *"20260328_draft_review_r1/review.md" ]]
}

# --- review: fails if source task has no result and no --artifact ---

@test "review: fails if source task has no result.md and no --artifact" {
    # Create task WITHOUT writing result.md
    "$SWARM_SCRIPT" task create --id 20260328_no_result --from mbp:1.0 --to mbp:5.0 \
        --prompt "Some task"

    run "$SWARM_SCRIPT" review 20260328_no_result --reviewer mbp:reviewer.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"result"* ]] || [[ "$output" == *"artifact"* ]]
}

# --- review: prompt references the artifact to review ---

@test "review: prompt references default result.md path when no --artifact" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local prompt_file="$SWARM_DIR/tasks/20260328_draft_review_r1/prompt.md"
    run cat "$prompt_file"
    [[ "$output" == *"20260328_draft/result.md"* ]]
}

# --- review: status.json is initialized correctly ---

@test "review: status.json initialized with state=dispatched" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    local state
    state=$(jq -r '.state' "$SWARM_DIR/tasks/20260328_draft_review_r1/status.json")
    [ "$state" = "dispatched" ]
}

# --- review: multiple rounds increment correctly ---

@test "review: three rounds create r1, r2, r3" {
    create_source_task "20260328_draft"
    create_agent_card "mbp:reviewer.0"

    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0
    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0
    "$SWARM_SCRIPT" review 20260328_draft --reviewer mbp:reviewer.0

    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r1" ]
    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r2" ]
    [ -d "$SWARM_DIR/tasks/20260328_draft_review_r3" ]
}

# --- review: missing --reviewer flag ---

@test "review: fails if --reviewer is missing" {
    create_source_task "20260328_draft"

    run "$SWARM_SCRIPT" review 20260328_draft
    [ "$status" -ne 0 ]
    [[ "$output" == *"--reviewer"* ]]
}
