#!/usr/bin/env bats
# Tests for swarm resume-all

setup() {
    export SWARM_DIR="$BATS_TMPDIR/test_swarm_$$"
    export AGENTS_DIR="$SWARM_DIR/agents"
    mkdir -p "$AGENTS_DIR"

    # Resolve symlinks for swarm script path
    _src="${BATS_TEST_DIRNAME}/../scripts/swarm"
    while [ -L "$_src" ]; do _src="$(readlink "$_src")"; done
    SWARM="$(cd "$(dirname "$_src")" && pwd -P)/$(basename "$_src")"

    # Create mock tmux that simulates pane existence
    export MOCK_DIR="$BATS_TMPDIR/mock_$$"
    mkdir -p "$MOCK_DIR/bin"

    # Mock brew to return our mock dir (so TMUX_BIN resolves to $MOCK_DIR/bin/tmux)
    cat > "$MOCK_DIR/brew" << BREWMOCK
#!/bin/bash
echo "$MOCK_DIR"
BREWMOCK
    chmod +x "$MOCK_DIR/brew"

    # MOCK_DIR is exported, so the tmux mock reads it at runtime
    cat > "$MOCK_DIR/bin/tmux" << 'MOCK'
#!/bin/bash
# Mock tmux for resume-all tests
# $MOCK_DIR is inherited from the test environment
case "$1" in
    display-message)
        target="" fmt=""
        prev=""
        for arg in "$@"; do
            if [ "$prev" = "-t" ]; then
                target="$arg"
            fi
            # Last arg is the format string
            fmt="$arg"
            prev="$arg"
        done
        # Check if pane is in our "alive" list
        if [ -f "$MOCK_DIR/alive_panes" ] && grep -q "^${target}$" "$MOCK_DIR/alive_panes" 2>/dev/null; then
            case "$fmt" in
                *pane_title*)
                    if [ -f "$MOCK_DIR/cc_running" ] && grep -q "^${target}$" "$MOCK_DIR/cc_running" 2>/dev/null; then
                        printf '%s\n' "✳ [dev] test-agent"
                    else
                        echo "zsh"
                    fi
                    ;;
                *pane_pid*)
                    echo "12345"
                    ;;
                *)
                    echo "mock"
                    ;;
            esac
            exit 0
        else
            exit 1
        fi
        ;;
    send-keys)
        echo "$*" >> "$MOCK_DIR/send_keys.log"
        exit 0
        ;;
    list-panes)
        # For _refresh_stale_cards — return empty
        exit 0
        ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/bin/tmux"
    export PATH="$MOCK_DIR:$PATH"
    export TMUX="/tmp/tmux-test/default,12345,0"
}

teardown() {
    rm -rf "$SWARM_DIR" "$MOCK_DIR"
}

create_card() {
    local pane="$1" session_id="$2" cwd="${3:-/tmp}"
    local safe=$(echo "$pane" | tr ':.' '_')
    cat > "$AGENTS_DIR/${safe}.json" << EOF
{"pane":"$pane","session_id":"$session_id","cwd":"$cwd","pid":12345,"status":"idle"}
EOF
}

@test "resume-all: dry-run shows what would be resumed" {
    create_card "mbp:agent-one.0" "uuid-1111" "/tmp"
    create_card "mbp:agent-two.0" "uuid-2222" "/tmp"
    echo "mbp:agent-one.0" > "$MOCK_DIR/alive_panes"
    echo "mbp:agent-two.0" >> "$MOCK_DIR/alive_panes"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"WOULD RESUME"* ]]
    [[ "$output" == *"would resume 2/2"* ]]
    [ ! -f "$MOCK_DIR/send_keys.log" ]
}

@test "resume-all: skips panes where CC is already active" {
    create_card "mbp:active-agent.0" "uuid-active" "/tmp"
    echo "mbp:active-agent.0" > "$MOCK_DIR/alive_panes"
    echo "mbp:active-agent.0" > "$MOCK_DIR/cc_running"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
    [[ "$output" == *"1 already active"* ]]
}

@test "resume-all: skips gone panes" {
    create_card "mbp:dead-agent.0" "uuid-dead" "/tmp"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"GONE"* ]]
    [[ "$output" == *"1 panes gone"* ]]
}

@test "resume-all: sends correct cd and resume commands" {
    create_card "mbp:my-agent.0" "uuid-resume-me" "/tmp/workdir"
    echo "mbp:my-agent.0" > "$MOCK_DIR/alive_panes"
    mkdir -p /tmp/workdir

    run "$SWARM" resume-all --delay 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESUME"* ]]
    [ -f "$MOCK_DIR/send_keys.log" ]
    grep -q "cd.*/tmp/workdir" "$MOCK_DIR/send_keys.log"
    grep -q "resume.*uuid-resume-me" "$MOCK_DIR/send_keys.log"
}

@test "resume-all: respects --cmd flag" {
    create_card "mbp:cc2-agent.0" "uuid-cc2" "/tmp"
    echo "mbp:cc2-agent.0" > "$MOCK_DIR/alive_panes"

    run "$SWARM" resume-all --cmd cc2 --delay 0
    [ "$status" -eq 0 ]
    [ -f "$MOCK_DIR/send_keys.log" ]
    grep -q "cc2 --resume" "$MOCK_DIR/send_keys.log"
}

@test "resume-all: mixed — active, gone, and resumable" {
    create_card "mbp:agent-active.0" "uuid-a" "/tmp"
    create_card "mbp:agent-gone.0" "uuid-g" "/tmp"
    create_card "mbp:agent-resume.0" "uuid-r" "/tmp"

    echo "mbp:agent-active.0" > "$MOCK_DIR/alive_panes"
    echo "mbp:agent-resume.0" >> "$MOCK_DIR/alive_panes"
    echo "mbp:agent-active.0" > "$MOCK_DIR/cc_running"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
    [[ "$output" == *"GONE"* ]]
    [[ "$output" == *"WOULD RESUME"* ]]
    [[ "$output" == *"would resume 1/3"* ]]
    [[ "$output" == *"1 already active"* ]]
    [[ "$output" == *"1 panes gone"* ]]
}

@test "resume-all: skips cards with missing session_id" {
    local safe="mbp_bad-card_0"
    echo '{"pane":"mbp:bad-card.0","cwd":"/tmp","pid":0}' > "$AGENTS_DIR/${safe}.json"
    echo "mbp:bad-card.0" > "$MOCK_DIR/alive_panes"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
    [[ "$output" == *"invalid cards"* ]]
}

@test "resume-all: no cards produces clean output" {
    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would resume 0/0"* ]]
}

@test "resume-all: rejects cwd containing single quotes" {
    local safe="mbp_inject-agent_0"
    cat > "$AGENTS_DIR/${safe}.json" << 'EOF'
{"pane":"mbp:inject-agent.0","session_id":"uuid-inject","cwd":"/tmp/it's/here","pid":12345,"status":"idle"}
EOF
    echo "mbp:inject-agent.0" > "$MOCK_DIR/alive_panes"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"*"unsafe"* ]]
}

@test "resume-all: rejects session_id containing single quotes" {
    local safe="mbp_inject2_0"
    printf '%s\n' '{"pane":"mbp:inject2.0","session_id":"uuid'"'"'evil","cwd":"/tmp","pid":12345,"status":"idle"}' \
        > "$AGENTS_DIR/${safe}.json"
    echo "mbp:inject2.0" > "$MOCK_DIR/alive_panes"

    run "$SWARM" resume-all --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"*"unsafe"* ]]
}

@test "resume-all: --delay rejects non-integer" {
    run "$SWARM" resume-all --delay foo
    [ "$status" -ne 0 ]
}
