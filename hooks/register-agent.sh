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

# Build new v1 fields as JSON
NEW_FIELDS=$(jq -n \
    --arg pane "$PANE_TARGET" \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg jsonl_path "$JSONL_PATH" \
    --argjson pid $$ \
    --arg status "$STATUS" \
    --arg event "$EVENT" \
    --arg registered_at "$TIMESTAMP" \
    '{pane: $pane, session_id: $session_id, cwd: $cwd, jsonl_path: $jsonl_path,
      pid: $pid, status: $status, event: $event, registered_at: $registered_at}')

# Track idle_since: set when transitioning to idle
if [ "$STATUS" = "idle" ]; then
    NEW_FIELDS=$(echo "$NEW_FIELDS" | jq --arg ts "$TIMESTAMP" '. + {idle_since: $ts}')
fi

# Merge-update: preserve v2 fields (role, team, capabilities, current_task)
CARD_FILE="$AGENTS_DIR/${SAFE_NAME}.json"
if [ -f "$CARD_FILE" ]; then
    # Clear current_task when agent goes idle (task completed)
    if [ "$STATUS" = "idle" ]; then
        local_current=$(jq -r '.current_task // empty' "$CARD_FILE")
        if [ -n "$local_current" ]; then
            NEW_FIELDS=$(echo "$NEW_FIELDS" | jq --arg lt "$local_current" '. + {last_task_id: $lt, current_task: null}')
        fi
    fi
    jq -s '.[0] * .[1]' "$CARD_FILE" <(echo "$NEW_FIELDS") > "$CARD_FILE.tmp" \
        && mv "$CARD_FILE.tmp" "$CARD_FILE"
else
    echo "$NEW_FIELDS" > "$CARD_FILE"
fi
