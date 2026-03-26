#!/bin/bash
# register-agent.sh — Hook handler: register and track agent status in the swarm
#
# Called by SessionStart, UserPromptSubmit, and Stop hooks.
# SWARM_EVENT env var tells us which event triggered this.
# Reads hook context from stdin, writes agent info to ~/.claude-swarm/agents/<pane>.json
# Only registers if running inside a tmux pane.

set -euo pipefail

SWARM_DIR="$HOME/.claude-swarm"
AGENTS_DIR="$SWARM_DIR/agents"
mkdir -p "$AGENTS_DIR"

# Read hook context from stdin
CONTEXT=$(cat)

SESSION_ID=$(echo "$CONTEXT" | jq -r '.session_id // empty')
CWD=$(echo "$CONTEXT" | jq -r '.cwd // empty')

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Detect tmux pane — only register if inside tmux
if [ -z "${TMUX:-}" ]; then
    exit 0
fi

if command -v brew >/dev/null 2>&1; then
    TMUX_BIN="$(brew --prefix)/bin/tmux"
else
    TMUX_BIN="tmux"
fi

# Get pane target: session_name:window_index.pane_index
PANE_TARGET=$($TMUX_BIN display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || echo "")
if [ -z "$PANE_TARGET" ]; then
    exit 0
fi

# Sanitize pane target for filename (replace : and . with _)
SAFE_NAME=$(echo "$PANE_TARGET" | tr ':.' '_')

EVENT="${SWARM_EVENT:-SessionStart}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$EVENT" in
    SessionStart|Stop)
        STATUS="idle"
        ;;
    UserPromptSubmit)
        STATUS="busy"
        ;;
    *)
        STATUS="unknown"
        ;;
esac

# Resolve JSONL path for collect
RESOLVED_CWD="$CWD"
if [ -d "$CWD" ]; then
    RESOLVED_CWD=$(cd "$CWD" && pwd -P)
fi
ENCODED_PATH=$(echo "$RESOLVED_CWD" | sed 's|/|-|g')
JSONL_PATH="$HOME/.claude/projects/${ENCODED_PATH}/${SESSION_ID}.jsonl"

# Write agent registration with status
cat > "$AGENTS_DIR/${SAFE_NAME}.json" <<EOF
{
  "pane": "$PANE_TARGET",
  "session_id": "$SESSION_ID",
  "cwd": "$CWD",
  "jsonl_path": "$JSONL_PATH",
  "pid": $$,
  "status": "$STATUS",
  "event": "$EVENT",
  "registered_at": "$TIMESTAMP"
}
EOF
