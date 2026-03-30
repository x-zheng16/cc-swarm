#!/usr/bin/env bats
# Tests for swarm merge: git merge coordinator

setup() {
    export SWARM_DIR="$BATS_TMPDIR/swarm_test_$$"
    export HOME="$BATS_TMPDIR/home_$$"
    mkdir -p "$SWARM_DIR/agents" "$SWARM_DIR/tasks" "$HOME"

    SWARM_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/swarm"

    # Create a test git repo with a base commit
    export TEST_REPO="$BATS_TMPDIR/repo_$$"
    mkdir -p "$TEST_REPO"
    git -C "$TEST_REPO" init -b main
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"
    echo "base content" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "initial commit"
}

teardown() {
    rm -rf "$SWARM_DIR" "$HOME" "$TEST_REPO"
    # Clean up any worktrees
    rm -rf "$BATS_TMPDIR/wt_"*"_$$"
}

# Helper: create a branch with changes in the test repo
create_branch_with_changes() {
    local branch="$1"
    local filename="$2"
    local content="$3"

    git -C "$TEST_REPO" checkout -b "$branch" main
    echo "$content" > "$TEST_REPO/$filename"
    git -C "$TEST_REPO" add "$filename"
    git -C "$TEST_REPO" commit -m "changes on $branch"
    git -C "$TEST_REPO" checkout main
}

# --- dry-run: clean merge detection ---

@test "merge: dry-run detects clean merge" {
    create_branch_with_changes "feature-a" "file_a.txt" "content a"
    create_branch_with_changes "feature-b" "file_b.txt" "content b"

    run "$SWARM_SCRIPT" merge --base main --sources feature-a,feature-b \
        --dry-run --repo "$TEST_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN"* ]]
    [[ "$output" != *"CONFLICT"* ]]
}

# --- dry-run: conflict detection ---

@test "merge: dry-run detects conflict" {
    # Branch modifies same file as main -> real conflict
    git -C "$TEST_REPO" checkout -b "conflict-branch" main
    echo "branch version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "conflict-branch changes base.txt"
    git -C "$TEST_REPO" checkout main

    # Also modify base.txt on main
    echo "main version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "main changes base.txt"

    run "$SWARM_SCRIPT" merge --base main --sources conflict-branch \
        --dry-run --repo "$TEST_REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"CONFLICT"* ]]
    [[ "$output" == *"base.txt"* ]]
}

# --- --sources filters branches ---

@test "merge: --sources filters to specified branches only" {
    create_branch_with_changes "branch-x" "x.txt" "x"
    create_branch_with_changes "branch-y" "y.txt" "y"
    create_branch_with_changes "branch-z" "z.txt" "z"

    run "$SWARM_SCRIPT" merge --base main --sources branch-x,branch-y \
        --dry-run --repo "$TEST_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"branch-x"* ]]
    [[ "$output" == *"branch-y"* ]]
    [[ "$output" != *"branch-z"* ]]
}

# --- sequential merge succeeds ---

@test "merge: sequential merge for clean branches" {
    create_branch_with_changes "feat-1" "one.txt" "one"
    create_branch_with_changes "feat-2" "two.txt" "two"

    run "$SWARM_SCRIPT" merge --base main --sources feat-1,feat-2 \
        --repo "$TEST_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Merged"* ]]

    # Verify both files exist on main
    git -C "$TEST_REPO" checkout main
    [ -f "$TEST_REPO/one.txt" ]
    [ -f "$TEST_REPO/two.txt" ]
}

# --- merge aborts on conflict ---

@test "merge: aborts when conflict detected (no --force)" {
    create_branch_with_changes "clean-branch" "clean.txt" "clean"

    git -C "$TEST_REPO" checkout -b "bad-branch" main
    echo "bad version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "conflicting change"
    git -C "$TEST_REPO" checkout main
    # Modify base.txt on main too
    echo "main version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "main change"

    run "$SWARM_SCRIPT" merge --base main --sources clean-branch,bad-branch \
        --repo "$TEST_REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"CONFLICT"* ]]
    [[ "$output" == *"Aborting"* ]]
}

# --- auto-detects worktree branches ---

@test "merge: auto-detects worktree branches (no --sources)" {
    create_branch_with_changes "wt-alpha" "alpha.txt" "alpha"
    create_branch_with_changes "wt-beta" "beta.txt" "beta"

    # Create worktrees for those branches
    git -C "$TEST_REPO" worktree add "$BATS_TMPDIR/wt_alpha_$$" wt-alpha 2>/dev/null
    git -C "$TEST_REPO" worktree add "$BATS_TMPDIR/wt_beta_$$" wt-beta 2>/dev/null

    run "$SWARM_SCRIPT" merge --base main --dry-run --repo "$TEST_REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wt-alpha"* ]]
    [[ "$output" == *"wt-beta"* ]]
    [[ "$output" == *"2 branch"* ]]

    # Cleanup worktrees
    git -C "$TEST_REPO" worktree remove "$BATS_TMPDIR/wt_alpha_$$" 2>/dev/null || true
    git -C "$TEST_REPO" worktree remove "$BATS_TMPDIR/wt_beta_$$" 2>/dev/null || true
}

# --- --force skips conflict check ---

@test "merge: --force merges clean branches despite conflicts" {
    create_branch_with_changes "ok-branch" "ok.txt" "ok content"

    # Create a conflicting branch
    git -C "$TEST_REPO" checkout -b "conflict-force" main
    echo "force version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "force conflict"
    git -C "$TEST_REPO" checkout main
    echo "main force version" > "$TEST_REPO/base.txt"
    git -C "$TEST_REPO" add base.txt
    git -C "$TEST_REPO" commit -m "main force"

    # Without --force: would abort. With --force: merges clean branches only.
    run "$SWARM_SCRIPT" merge --base main --sources ok-branch,conflict-force \
        --force --repo "$TEST_REPO"
    # Should succeed (merges what it can)
    [[ "$output" == *"CONFLICT"* ]]
    [[ "$output" == *"Merged ok-branch"* ]]

    # Verify ok.txt made it to main
    git -C "$TEST_REPO" checkout main
    [ -f "$TEST_REPO/ok.txt" ]
}

# --- fails when no sources ---

@test "merge: fails when no source branches found" {
    run "$SWARM_SCRIPT" merge --base main --dry-run --repo "$TEST_REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No source branches"* ]]
}

# --- fails when base doesn't exist ---

@test "merge: fails when base branch doesn't exist" {
    run "$SWARM_SCRIPT" merge --base nonexistent --sources main \
        --dry-run --repo "$TEST_REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- merge report shows stats ---

@test "merge: report shows file change stats" {
    create_branch_with_changes "stats-branch" "new_file.txt" "some content"

    run "$SWARM_SCRIPT" merge --base main --sources stats-branch \
        --dry-run --repo "$TEST_REPO"
    [ "$status" -eq 0 ]
    # Should show file count
    [[ "$output" == *"file"* ]]
}
