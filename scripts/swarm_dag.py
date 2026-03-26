#!/usr/bin/env python3
"""DAG executor for CC Swarm.

Reads a dag.json file, validates the dependency graph, and orchestrates
task dispatch/polling across tmux-based Claude Code sessions.

Usage:
    swarm run <dag.json> [--resume] [--dry-run] [--poll-interval N] [--timeout N]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path

SWARM_DIR = Path.home() / ".claude-swarm"
AGENTS_DIR = SWARM_DIR / "agents"
STATUS_FRESHNESS = 120  # seconds
DISPATCH_GRACE = 15  # seconds after dispatch before accepting idle as completion


# --- DAG Validation ---


def validate_and_sort(tasks: dict) -> tuple[list[str], list[str]]:
    """Validate DAG and return (topological_order, errors).

    Uses Kahn's algorithm for cycle detection and topological sorting.
    Returns (order, []) on success, ([], errors) on failure.
    """
    errors = []

    # Check required fields
    for name, spec in tasks.items():
        if "target" not in spec:
            errors.append(f"Task '{name}': missing required field 'target'")
        if "prompt" not in spec and "prompt_file" not in spec:
            errors.append(f"Task '{name}': must have 'prompt' or 'prompt_file'")
        if "prompt_file" in spec:
            path = os.path.expanduser(spec["prompt_file"])
            if not os.path.isfile(path):
                errors.append(f"Task '{name}': prompt_file not found: {path}")
        join = spec.get("join", "and")
        if join not in ("and", "or"):
            errors.append(f"Task '{name}': join must be 'and' or 'or', got '{join}'")
        for dep in spec.get("depends_on", []):
            if dep not in tasks:
                errors.append(f"Task '{name}': depends on unknown task '{dep}'")

    if errors:
        return [], errors

    # Check target reuse: no two concurrent tasks should share a target
    # Build adjacency for concurrency analysis
    children = defaultdict(list)
    in_degree = {name: 0 for name in tasks}
    for name, spec in tasks.items():
        for dep in spec.get("depends_on", []):
            in_degree[name] += 1
            children[dep].append(name)

    # Kahn's BFS with deterministic ordering
    queue = deque(sorted(n for n, d in in_degree.items() if d == 0))
    topo_order = []
    while queue:
        node = queue.popleft()
        topo_order.append(node)
        for child in sorted(children[node]):
            in_degree[child] -= 1
            if in_degree[child] == 0:
                queue.append(child)

    if len(topo_order) != len(tasks):
        cycle_nodes = [n for n, d in in_degree.items() if d > 0]
        errors.append(f"Cycle detected involving tasks: {', '.join(cycle_nodes)}")
        return [], errors

    # Warn about target reuse at the same topological level (concurrent tasks)
    level = {}
    for name in topo_order:
        deps = tasks[name].get("depends_on", [])
        level[name] = 0 if not deps else max(level[d] for d in deps) + 1

    targets_by_level = defaultdict(list)
    for name in topo_order:
        targets_by_level[(level[name], tasks[name]["target"])].append(name)
    for (lv, target), names in targets_by_level.items():
        if len(names) > 1:
            errors.append(
                f"Warning: tasks {', '.join(names)} share target '{target}' at level {lv} "
                f"(may run concurrently -- ensure they don't overlap)"
            )

    return topo_order, errors


# --- Status Detection ---


def get_agent_status(target: str) -> str:
    """Get agent status by reading registry JSON directly."""
    safe_name = target.replace(":", "_").replace(".", "_")
    agent_file = AGENTS_DIR / f"{safe_name}.json"

    if agent_file.exists():
        try:
            data = json.loads(agent_file.read_text())
            status = data.get("status", "")
            registered_at = data.get("registered_at", "")
            if status and registered_at:
                try:
                    ts = datetime.fromisoformat(registered_at.replace("Z", "+00:00"))
                    age = (datetime.now(timezone.utc) - ts).total_seconds()
                    if age < STATUS_FRESHNESS:
                        return status
                except (ValueError, TypeError):
                    pass
        except (json.JSONDecodeError, OSError):
            pass

    # Fallback: check pane content heuristics
    try:
        result = subprocess.run(
            ["swarm", "monitor", target, "--tail", "15"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        text = result.stdout.strip()

        # Same heuristics as bash get_status
        if re.search(r"^\s*>|bypass permissions|permissions on|has exited", text, re.M):
            return "idle"
        if re.search(r"\d+\.\d+\.\d+\s+(Opus|Sonnet|Haiku)", text):
            return "idle"
        if re.search(r"(Bash|Read|Edit|Write|Grep|Glob|Agent):\d+", text):
            return "idle"
        if "\u2500\u2500\u2500\u2500\u2500" in text:  # box-drawing: ─────
            return "idle"
        if re.search(r"Thinking|[\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f]|Processing|Running", text):
            return "busy"
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return "unknown"


# --- State Management ---


def state_path(dag_file: str) -> Path:
    """Return dag_state.json path alongside the dag file."""
    return Path(dag_file).with_name(
        Path(dag_file).stem + "_state.json"
    )


def load_state(dag_file: str) -> dict | None:
    """Load existing state file if present."""
    sp = state_path(dag_file)
    if sp.exists():
        try:
            return json.loads(sp.read_text())
        except (json.JSONDecodeError, OSError):
            return None
    return None


def save_state(dag_file: str, state: dict):
    """Atomically save state to disk."""
    sp = state_path(dag_file)
    tmp = sp.with_suffix(".tmp")
    state["updated_at"] = now_iso()
    tmp.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n")
    tmp.rename(sp)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s: str) -> float:
    """Parse ISO timestamp to epoch seconds."""
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt.timestamp()
    except (ValueError, TypeError):
        return 0.0


# --- Dispatch ---


def dispatch_task(name: str, spec: dict) -> bool:
    """Dispatch a task via swarm dispatch. Returns True on success."""
    target = spec["target"]
    # Use list form for subprocess to avoid shell injection
    cmd = ["swarm", "dispatch", target]

    if "prompt_file" in spec:
        path = os.path.expanduser(spec["prompt_file"])
        cmd.extend(["--file", path])
    else:
        cmd.append(spec["prompt"])

    # Force dispatch (agent might show as unknown during status transition)
    cmd.append("--force")

    print(f"  [{name}] -> {target}", flush=True)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            print(f"  [{name}] dispatch failed: {result.stderr.strip()}", flush=True)
            return False
        return True
    except subprocess.TimeoutExpired:
        print(f"  [{name}] dispatch timed out", flush=True)
        return False


def validate_outputs(spec: dict) -> bool:
    """Check that declared output files exist."""
    for output in spec.get("outputs", []):
        path = os.path.expanduser(output)
        if not os.path.exists(path):
            return False
    return True


# --- Main Executor ---


def compute_ready(tasks: dict, task_states: dict) -> tuple[list[str], bool]:
    """Find tasks ready to dispatch. Returns (ready_list, any_newly_skipped)."""
    ready = []
    any_skipped = False
    for name, spec in tasks.items():
        if task_states[name]["status"] != "pending":
            continue

        deps = spec.get("depends_on", [])
        if not deps:
            ready.append(name)
            continue

        join = spec.get("join", "and")
        dep_statuses = [task_states[d]["status"] for d in deps]

        if join == "and":
            if all(s == "completed" for s in dep_statuses):
                ready.append(name)
            elif any(s in ("failed", "skipped") for s in dep_statuses):
                task_states[name]["status"] = "skipped"
                failed_deps = [d for d in deps if task_states[d]["status"] in ("failed", "skipped")]
                task_states[name]["reason"] = f"dependency '{failed_deps[0]}' failed"
                print(f"  [{name}] skipped: {task_states[name]['reason']}", flush=True)
                any_skipped = True
        elif join == "or":
            if any(s == "completed" for s in dep_statuses):
                ready.append(name)
            elif all(s in ("failed", "skipped") for s in dep_statuses):
                task_states[name]["status"] = "skipped"
                task_states[name]["reason"] = "all dependencies failed"
                print(f"  [{name}] skipped: all dependencies failed", flush=True)
                any_skipped = True

    return ready, any_skipped


def print_dag_summary(dag: dict, topo: list[str]):
    """Print DAG structure summary."""
    tasks = dag["tasks"]
    max_par = dag.get("max_parallel", 3)
    dag_id = dag.get("id", "(unnamed)")

    print(f"\nDAG: {dag_id}")
    print(f"Tasks: {len(tasks)}, Max parallel: {max_par}")
    print(f"Execution order:")

    # Group by topological level
    level = {}
    for name in topo:
        deps = tasks[name].get("depends_on", [])
        if not deps:
            level[name] = 0
        else:
            level[name] = max(level[d] for d in deps) + 1

    max_level = max(level.values()) if level else 0
    for lv in range(max_level + 1):
        names_at_level = [n for n in topo if level[n] == lv]
        for i, name in enumerate(names_at_level):
            join = tasks[name].get("join", "and")
            deps = tasks[name].get("depends_on", [])
            dep_str = ""
            if deps:
                dep_str = f" <- {join}({', '.join(deps)})"
            par = " |" if i > 0 else "  "
            if i == 0 and len(names_at_level) > 1:
                par = " /"
            print(f"  L{lv}{par} {name} @ {tasks[name]['target']}{dep_str}")
    print()


def run_dag(dag_file: str, resume: bool = False, dry_run: bool = False,
            poll_interval: int = 10, timeout: int = 3600):
    """Main DAG execution loop."""
    # Load and validate
    dag_path = Path(dag_file)
    if not dag_path.exists():
        print(f"Error: {dag_file} not found", file=sys.stderr)
        return 1

    dag = json.loads(dag_path.read_text())
    tasks = dag.get("tasks", {})
    max_parallel = dag.get("max_parallel", 3)

    if not tasks:
        print("Error: no tasks defined in DAG", file=sys.stderr)
        return 1

    topo, errors = validate_and_sort(tasks)
    # Separate warnings from hard errors
    warnings = [e for e in errors if e.startswith("Warning:")]
    hard_errors = [e for e in errors if not e.startswith("Warning:")]

    if hard_errors:
        print("DAG validation failed:", file=sys.stderr)
        for e in hard_errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    for w in warnings:
        print(f"  {w}", file=sys.stderr)

    print_dag_summary(dag, topo)

    if dry_run:
        print("(dry run -- no tasks dispatched)")
        return 0

    # Initialize or resume state
    state = None
    if resume:
        state = load_state(dag_file)
        if state:
            print(f"Resuming from {state_path(dag_file)}")

    if not state:
        state = {
            "dag_id": dag.get("id", dag_path.stem),
            "dag_file": str(dag_path.resolve()),
            "started_at": now_iso(),
            "tasks": {name: {"status": "pending"} for name in tasks},
        }

    task_states = state["tasks"]
    # Ensure new tasks added since last run get pending status
    for name in tasks:
        if name not in task_states:
            task_states[name] = {"status": "pending"}

    # Track which targets are currently occupied by running tasks
    occupied_targets: set[str] = set()
    for name, ts in task_states.items():
        if ts["status"] == "running":
            occupied_targets.add(tasks[name]["target"])

    save_state(dag_file, state)

    # Summary of resumed state
    if resume:
        completed = [n for n, s in task_states.items() if s["status"] == "completed"]
        if completed:
            print(f"Already completed: {', '.join(completed)}")

    # Main loop
    start_time = time.time()
    while True:
        elapsed = time.time() - start_time
        if elapsed > timeout:
            print(f"\nDAG timeout after {int(elapsed)}s", file=sys.stderr)
            for name, ts in task_states.items():
                if ts["status"] == "running":
                    ts["status"] = "failed"
                    ts["failed_at"] = now_iso()
                    ts["error"] = "dag timeout"
            save_state(dag_file, state)
            break

        # Check running tasks
        running = [n for n, s in task_states.items() if s["status"] == "running"]
        for name in running:
            target = tasks[name]["target"]
            status = get_agent_status(target)
            if status == "idle":
                # Grace period: don't accept idle until agent has had time to start
                dispatched_at = task_states[name].get("dispatched_at", "")
                if dispatched_at:
                    elapsed_since_dispatch = time.time() - parse_iso(dispatched_at)
                    if elapsed_since_dispatch < DISPATCH_GRACE:
                        continue  # too early, agent may not have started yet

                # Task completed -- validate outputs
                if validate_outputs(tasks[name]):
                    task_states[name]["status"] = "completed"
                    task_states[name]["completed_at"] = now_iso()
                    occupied_targets.discard(target)
                    print(f"  [{name}] completed", flush=True)
                else:
                    missing = [
                        o for o in tasks[name].get("outputs", [])
                        if not os.path.exists(os.path.expanduser(o))
                    ]
                    task_states[name]["status"] = "failed"
                    task_states[name]["failed_at"] = now_iso()
                    task_states[name]["error"] = f"missing outputs: {', '.join(missing)}"
                    occupied_targets.discard(target)
                    print(f"  [{name}] failed: missing outputs: {', '.join(missing)}", flush=True)
                save_state(dag_file, state)

        # Compute ready set (also marks skipped tasks)
        ready, any_skipped = compute_ready(tasks, task_states)
        if any_skipped:
            save_state(dag_file, state)

        # Filter ready tasks: skip if their target is already occupied
        ready = [n for n in ready if tasks[n]["target"] not in occupied_targets]

        running_count = sum(1 for s in task_states.values() if s["status"] == "running")
        slots = max_parallel - running_count

        # Dispatch ready tasks
        if ready and slots > 0:
            to_dispatch = ready[:slots]
            print(f"\nDispatching {len(to_dispatch)} task(s):", flush=True)
            for name in to_dispatch:
                ok = dispatch_task(name, tasks[name])
                if ok:
                    task_states[name]["status"] = "running"
                    task_states[name]["dispatched_at"] = now_iso()
                    occupied_targets.add(tasks[name]["target"])
                else:
                    task_states[name]["status"] = "failed"
                    task_states[name]["failed_at"] = now_iso()
                    task_states[name]["error"] = "dispatch failed"
            save_state(dag_file, state)

        # Check termination
        terminal = sum(
            1 for s in task_states.values()
            if s["status"] in ("completed", "failed", "skipped")
        )
        if terminal == len(tasks):
            break

        # Recompute running count after dispatch for accurate deadlock check
        running_count = sum(1 for s in task_states.values() if s["status"] == "running")
        pending = sum(1 for s in task_states.values() if s["status"] == "pending")
        if running_count == 0 and not ready and pending > 0:
            print("\nDeadlock: no running tasks and no ready tasks, but pending tasks remain",
                  file=sys.stderr)
            for name, ts in task_states.items():
                if ts["status"] == "pending":
                    ts["status"] = "skipped"
                    ts["reason"] = "deadlock"
            save_state(dag_file, state)
            break

        # Progress heartbeat
        if running:
            print(f"  [{int(elapsed)}s] {running_count} running, {pending} pending", flush=True)

        # Poll interval
        time.sleep(poll_interval)

    # Final report
    print(f"\n{'=' * 50}")
    print(f"DAG: {dag.get('id', dag_path.stem)}")
    completed = [n for n, s in task_states.items() if s["status"] == "completed"]
    failed = [n for n, s in task_states.items() if s["status"] == "failed"]
    skipped = [n for n, s in task_states.items() if s["status"] == "skipped"]
    print(f"Completed: {len(completed)}/{len(tasks)}")
    if completed:
        print(f"  {', '.join(completed)}")
    if failed:
        print(f"Failed: {len(failed)}")
        for n in failed:
            err = task_states[n].get("error", "unknown")
            print(f"  {n}: {err}")
    if skipped:
        print(f"Skipped: {len(skipped)}")
        for n in skipped:
            reason = task_states[n].get("reason", "unknown")
            print(f"  {n}: {reason}")
    print(f"State saved: {state_path(dag_file)}")
    print(f"{'=' * 50}")

    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description="CC Swarm DAG executor")
    parser.add_argument("dag_file", help="Path to dag.json")
    parser.add_argument("--resume", action="store_true",
                        help="Resume from existing state file")
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate and print execution plan without dispatching")
    parser.add_argument("--poll-interval", type=int, default=10,
                        help="Seconds between status polls (default: 10)")
    parser.add_argument("--timeout", type=int, default=3600,
                        help="Max seconds for entire DAG execution (default: 3600)")
    args = parser.parse_args()

    sys.exit(run_dag(
        args.dag_file,
        resume=args.resume,
        dry_run=args.dry_run,
        poll_interval=args.poll_interval,
        timeout=args.timeout,
    ))


if __name__ == "__main__":
    main()
