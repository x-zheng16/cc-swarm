#!/bin/bash
# swarm_lock.sh — Atomic mkdir-based file locking with PID stale detection
# Source this file to use: swarm_lock, swarm_unlock, with_lock

# Acquire a lock. Returns 0 on success, 1 if held by a live process.
# Usage: swarm_lock /path/to/lock_dir
swarm_lock() {
    local lock_dir="$1"

    if mkdir "$lock_dir" 2>/dev/null; then
        echo $$ > "$lock_dir/pid"
        return 0
    fi

    # Lock exists — check if holder is alive
    if [ -f "$lock_dir/pid" ]; then
        local held_pid
        held_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
        if [ -n "$held_pid" ] && kill -0 "$held_pid" 2>/dev/null; then
            # Held by a live process
            return 1
        fi
        # Stale lock — reap and re-acquire
        rm -rf "$lock_dir"
        if mkdir "$lock_dir" 2>/dev/null; then
            echo $$ > "$lock_dir/pid"
            return 0
        fi
    fi

    return 1
}

# Release a lock.
# Usage: swarm_unlock /path/to/lock_dir
swarm_unlock() {
    local lock_dir="$1"
    rm -rf "$lock_dir"
}

# Run a command under lock. Lock is always released, even on failure.
# Usage: with_lock /path/to/lock_dir command [args...]
with_lock() {
    local lock_dir="$1"
    shift

    swarm_lock "$lock_dir" || return 1
    local rc=0
    "$@" || rc=$?
    swarm_unlock "$lock_dir"
    return $rc
}
