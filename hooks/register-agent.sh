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

# Resolve pane target for display-message: use $TMUX_PANE if available (always correct),
# fall back to no -t (may return focused pane — less reliable but better than nothing).
DISPLAY_TARGET="${TMUX_PANE:-}"
DISPLAY_FLAG=""
if [ -n "$DISPLAY_TARGET" ]; then
    DISPLAY_FLAG="-t $DISPLAY_TARGET"
fi

# Get pane ID for reliable targeting
# shellcheck disable=SC2086
PANE_ID=$($TMUX_BIN display-message -p $DISPLAY_FLAG '#{pane_id}' 2>/dev/null || echo "")

# Get pane target: session_name:window_name.pane_index
# Window name sync is handled by tmux pane-title-changed hook (sync_window_name.sh)
# shellcheck disable=SC2086
PANE_TARGET=$($TMUX_BIN display-message -p -t "${PANE_ID:-$DISPLAY_TARGET}" '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || echo "")
if [ -z "$PANE_TARGET" ]; then
    exit 0
fi

# Sanitize pane target for filename (replace : and . with _)
SAFE_NAME=$(echo "$PANE_TARGET" | tr ':.' '_')

EVENT="${SWARM_EVENT:-SessionStart}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# On Stop: delete this agent's card and prune stale cards, then exit
if [ "$EVENT" = "Stop" ]; then
    SAFE_NAME=$(echo "$PANE_TARGET" | tr ':.' '_')
    rm -f "$AGENTS_DIR/${SAFE_NAME}.json"
    # Also delete any card with matching session_id (handles renamed cards)
    for old_card in "$AGENTS_DIR"/*.json; do
        [ -f "$old_card" ] || continue
        old_sid=$(jq -r '.session_id // empty' "$old_card" 2>/dev/null)
        if [ "$old_sid" = "$SESSION_ID" ]; then
            rm -f "$old_card"
        fi
    done
    exit 0
fi

# Periodic stale card pruning: on every hook fire, remove cards whose pane is dead.
# Rate-limit: only run if last prune was >60s ago (avoid slowing down every prompt).
PRUNE_MARKER="$SWARM_DIR/.last_card_prune"
should_prune=false
if [ ! -f "$PRUNE_MARKER" ]; then
    should_prune=true
else
    last_prune=$(stat -f %m "$PRUNE_MARKER" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $((now - last_prune)) -gt 60 ]; then
        should_prune=true
    fi
fi
if [ "$should_prune" = true ]; then
    touch "$PRUNE_MARKER"
    # Build set of all live pane targets (session:window.pane_index)
    live_panes=$($TMUX_BIN list-panes -a -F '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || echo "")
    for card in "$AGENTS_DIR"/*.json; do
        [ -f "$card" ] || continue
        card_pane=$(jq -r '.pane // empty' "$card" 2>/dev/null)
        [ -z "$card_pane" ] && continue
        # Check exact pane target match against live panes
        if ! echo "$live_panes" | grep -qxF "$card_pane"; then
            rm -f "$card"
        fi
    done
fi

# Status is primarily read from pane_title (✳=idle, ⠂/⠐=busy) by swarm CLI.
# Card status is a secondary record for offline/historical use only.
STATUS="idle"
[ "$EVENT" = "UserPromptSubmit" ] && STATUS="busy"

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
    --argjson pid "$($TMUX_BIN display-message -p -t "${PANE_ID:-${TMUX_PANE:-}}" '#{pane_pid}' 2>/dev/null || echo 0)" \
    --arg status "$STATUS" \
    --arg event "$EVENT" \
    --arg registered_at "$TIMESTAMP" \
    '{pane: $pane, session_id: $session_id, cwd: $cwd, jsonl_path: $jsonl_path,
      pid: $pid, status: $status, event: $event, registered_at: $registered_at}')

# Track idle_since: set when transitioning to idle, clear on busy
if [ "$STATUS" = "idle" ]; then
    NEW_FIELDS=$(echo "$NEW_FIELDS" | jq --arg ts "$TIMESTAMP" '. + {idle_since: $ts}')
elif [ "$STATUS" = "busy" ]; then
    NEW_FIELDS=$(echo "$NEW_FIELDS" | jq '. + {idle_since: null}')
fi

# Heartbeat: always update timestamp on every hook fire
NEW_FIELDS=$(echo "$NEW_FIELDS" | jq --arg ts "$TIMESTAMP" '. + {last_heartbeat: $ts}')

# Clean up stale cards: if window was renamed, old card has same session_id but different filename.
# Migrate metadata (role, team, capabilities, current_task) from old card before deleting it.
CARD_FILE="$AGENTS_DIR/${SAFE_NAME}.json"
MIGRATED_FIELDS=""
for old_card in "$AGENTS_DIR"/*.json; do
    [ -f "$old_card" ] || continue
    [ "$old_card" = "$CARD_FILE" ] && continue
    old_sid=$(jq -r '.session_id // empty' "$old_card" 2>/dev/null)
    if [ "$old_sid" = "$SESSION_ID" ]; then
        # Same session, different filename — stale card from before rename
        MIGRATED_FIELDS=$(jq '{role, team, capabilities, current_task, last_task_id} | with_entries(select(.value != null))' "$old_card" 2>/dev/null || echo "")
        rm -f "$old_card"
    fi
done

# Merge-update: preserve existing fields (role, team, capabilities, current_task)
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
    # Apply migrated metadata from old card (if rename happened)
    if [ -n "$MIGRATED_FIELDS" ] && [ "$MIGRATED_FIELDS" != "{}" ]; then
        NEW_FIELDS=$(echo "$NEW_FIELDS" | jq --argjson mf "$MIGRATED_FIELDS" '. * $mf')
    fi
    echo "$NEW_FIELDS" > "$CARD_FILE"
fi

