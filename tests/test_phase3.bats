#!/usr/bin/env bats
# Phase 3 tests: Topology Management

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

# --- swarm team create ---

@test "team create: creates topology.json with correct structure" {
    "$SWARM_SCRIPT" team create safety-team --lead mbp:coordinator.0 --desc "Safety research team"

    [ -f "$SWARM_DIR/topology.json" ]

    # Verify team structure
    [ "$(jq -r '.teams["safety-team"].lead' "$SWARM_DIR/topology.json")" = "mbp:coordinator.0" ]
    [ "$(jq -r '.teams["safety-team"].description' "$SWARM_DIR/topology.json")" = "Safety research team" ]
    [ "$(jq -r '.teams["safety-team"].members | length' "$SWARM_DIR/topology.json")" = "0" ]
}

@test "team create: initializes top-level fields on first create" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0

    # special_agents and spawn_permissions should exist
    [ "$(jq -r '.special_agents | type' "$SWARM_DIR/topology.json")" = "object" ]
    [ "$(jq -r '.spawn_permissions | type' "$SWARM_DIR/topology.json")" = "object" ]
}

@test "team create: merges into existing topology.json" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0 --desc "Alpha team"
    "$SWARM_SCRIPT" team create beta --lead mbp:2.0 --desc "Beta team"

    # Both teams should exist
    [ "$(jq -r '.teams | keys | length' "$SWARM_DIR/topology.json")" = "2" ]
    [ "$(jq -r '.teams["alpha"].lead' "$SWARM_DIR/topology.json")" = "mbp:1.0" ]
    [ "$(jq -r '.teams["beta"].lead' "$SWARM_DIR/topology.json")" = "mbp:2.0" ]
}

@test "team create: rejects duplicate team name" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0

    run "$SWARM_SCRIPT" team create alpha --lead mbp:2.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "team create: rejects missing --lead" {
    run "$SWARM_SCRIPT" team create alpha
    [ "$status" -ne 0 ]
    [[ "$output" == *"--lead"* ]]
}

# --- swarm team add ---

@test "team add: adds member to existing team" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0

    [ "$(jq -r '.teams["alpha"].members | length' "$SWARM_DIR/topology.json")" = "1" ]
    [ "$(jq -r '.teams["alpha"].members[0]' "$SWARM_DIR/topology.json")" = "mbp:agent1.0" ]
}

@test "team add: adds multiple members" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent2.0

    [ "$(jq -r '.teams["alpha"].members | length' "$SWARM_DIR/topology.json")" = "2" ]
    [ "$(jq -r '.teams["alpha"].members[1]' "$SWARM_DIR/topology.json")" = "mbp:agent2.0" ]
}

@test "team add: rejects duplicate member" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0

    run "$SWARM_SCRIPT" team add alpha mbp:agent1.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"already a member"* ]]
}

@test "team add: rejects nonexistent team" {
    run "$SWARM_SCRIPT" team add nonexistent mbp:agent1.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- swarm team remove ---

@test "team remove: removes member from team" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0
    "$SWARM_SCRIPT" team add alpha mbp:agent2.0

    "$SWARM_SCRIPT" team remove alpha mbp:agent1.0

    [ "$(jq -r '.teams["alpha"].members | length' "$SWARM_DIR/topology.json")" = "1" ]
    [ "$(jq -r '.teams["alpha"].members[0]' "$SWARM_DIR/topology.json")" = "mbp:agent2.0" ]
}

@test "team remove: rejects nonexistent member" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0

    run "$SWARM_SCRIPT" team remove alpha mbp:ghost.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a member"* ]]
}

@test "team remove: rejects nonexistent team" {
    run "$SWARM_SCRIPT" team remove nonexistent mbp:agent1.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- swarm team show ---

@test "team show: displays team details" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0 --desc "The alpha team"
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0

    run "$SWARM_SCRIPT" team show alpha
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"mbp:1.0"* ]]
    [[ "$output" == *"The alpha team"* ]]
    [[ "$output" == *"mbp:agent1.0"* ]]
}

@test "team show: rejects nonexistent team" {
    run "$SWARM_SCRIPT" team show nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- swarm team list ---

@test "team list: lists all teams" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team create beta --lead mbp:2.0

    run "$SWARM_SCRIPT" team list
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "team list: shows empty message when no teams" {
    run "$SWARM_SCRIPT" team list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No teams"* ]]
}

# --- swarm team delete ---

@test "team delete: removes team from topology" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0
    "$SWARM_SCRIPT" team create beta --lead mbp:2.0

    "$SWARM_SCRIPT" team delete alpha

    [ "$(jq -r '.teams | keys | length' "$SWARM_DIR/topology.json")" = "1" ]
    [ "$(jq -r '.teams["alpha"] // "null"' "$SWARM_DIR/topology.json")" = "null" ]
    [ "$(jq -r '.teams["beta"].lead' "$SWARM_DIR/topology.json")" = "mbp:2.0" ]
}

@test "team delete: rejects nonexistent team" {
    run "$SWARM_SCRIPT" team delete nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# --- swarm topology ---

@test "topology: pretty-prints full topology" {
    "$SWARM_SCRIPT" team create alpha --lead mbp:1.0 --desc "Alpha team"
    "$SWARM_SCRIPT" team add alpha mbp:agent1.0

    run "$SWARM_SCRIPT" topology
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"mbp:1.0"* ]]
    [[ "$output" == *"mbp:agent1.0"* ]]
}

@test "topology: shows message when no topology exists" {
    run "$SWARM_SCRIPT" topology
    [ "$status" -eq 0 ]
    [[ "$output" == *"No topology"* ]]
}
