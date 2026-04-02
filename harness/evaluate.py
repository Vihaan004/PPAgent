#!/usr/bin/env python3
"""
Evaluation harness for PPA optimization benchmark.

Two-stage pipeline per solution:
  1. Correctness: iverilog compile + vvp simulate → PASS/FAIL
  2. PPA metrics: Yosys synthesis → cells, ffs, wires + delta vs baseline

Usage:
  python3 harness/evaluate.py --task benchmark/tasks/task_01 --solution solution.v
  python3 harness/evaluate.py --all --solutions-dir benchmark/solutions/manual
  python3 harness/evaluate.py --task benchmark/tasks/task_01 --solution solution.v --output results.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile


# ---------------------------------------------------------------------------
# Core functions (importable by the agent in Subtask 3)
# ---------------------------------------------------------------------------

def simulate(solution_file: str, testbench_file: str, timeout_s: int = 60) -> dict:
    """Compile with iverilog and run with vvp.

    Returns:
        {"pass": bool, "output": str, "stage": "compile"|"simulate"}
    """
    vvp_fd, vvp_path = tempfile.mkstemp(suffix=".vvp")
    os.close(vvp_fd)

    try:
        # Compile
        comp = subprocess.run(
            ["iverilog", "-o", vvp_path, solution_file, testbench_file],
            capture_output=True, text=True, timeout=30,
        )
        if comp.returncode != 0:
            return {"pass": False, "output": comp.stderr.strip(), "stage": "compile"}

        # Simulate
        sim = subprocess.run(
            ["vvp", vvp_path],
            capture_output=True, text=True, timeout=timeout_s,
        )
        output = (sim.stdout + "\n" + sim.stderr).strip()
        passed = "ALL TESTS PASSED" in output
        return {"pass": passed, "output": output, "stage": "simulate"}

    except subprocess.TimeoutExpired:
        return {"pass": False, "output": "TIMEOUT", "stage": "simulate"}
    finally:
        if os.path.exists(vvp_path):
            os.remove(vvp_path)


def synthesize(solution_file: str, top_module: str) -> dict:
    """Run Yosys synthesis and extract PPA metrics.

    Returns:
        {"cells": int, "ffs": int, "wires": int} on success,
        {"error": str} on failure.
    """
    log_fd, log_path = tempfile.mkstemp(suffix=".log")
    os.close(log_fd)

    try:
        yosys_cmd = f"read_verilog {solution_file}; synth -top {top_module}; stat"
        result = subprocess.run(
            ["yosys", "-p", yosys_cmd],
            capture_output=True, text=True, timeout=120,
        )

        log_text = result.stdout + "\n" + result.stderr
        # Write log for debugging
        with open(log_path, "w") as f:
            f.write(log_text)

        if result.returncode != 0:
            return {"error": f"Yosys failed (rc={result.returncode}): {result.stderr[:500]}"}

        return _parse_yosys_stats(log_text)

    except subprocess.TimeoutExpired:
        return {"error": "Yosys synthesis timed out (120s)"}
    finally:
        if os.path.exists(log_path):
            os.remove(log_path)


def _parse_yosys_stats(log_text: str) -> dict:
    """Extract cells, ffs, wires from Yosys stat output."""
    lines = log_text.split("\n")

    # Find the last "Printing statistics." block
    last_stat_idx = -1
    for i, line in enumerate(lines):
        if "Printing statistics." in line:
            last_stat_idx = i

    if last_stat_idx == -1:
        return {"error": "No statistics block found in Yosys output"}

    stat_lines = lines[last_stat_idx:]

    cells = 0
    wires = 0
    ffs = 0

    for line in stat_lines:
        if "Number of cells:" in line:
            m = re.search(r"(\d+)\s*$", line.strip())
            if m:
                cells = int(m.group(1))
        if "Number of wire bits:" in line:
            m = re.search(r"(\d+)\s*$", line.strip())
            if m:
                wires = int(m.group(1))
        if "_DFF_" in line:
            m = re.search(r"(\d+)\s*$", line.strip())
            if m:
                ffs += int(m.group(1))

    return {"cells": cells, "ffs": ffs, "wires": wires}


def load_task(task_dir: str) -> dict:
    """Load task metadata: baseline metrics, file paths."""
    baseline_path = os.path.join(task_dir, "baseline_metrics.json")
    testbench_path = os.path.join(task_dir, "testbench.v")
    original_path = os.path.join(task_dir, "original.v")

    if not os.path.isfile(baseline_path):
        raise FileNotFoundError(f"baseline_metrics.json not found in {task_dir}")
    if not os.path.isfile(testbench_path):
        raise FileNotFoundError(f"testbench.v not found in {task_dir}")

    with open(baseline_path) as f:
        baseline = json.load(f)

    return {
        "task_id": os.path.basename(task_dir),
        "task_dir": task_dir,
        "testbench": testbench_path,
        "original": original_path,
        "baseline": baseline,
        "top_module": baseline["top_module"],
    }


def compute_deltas(baseline: dict, solution_metrics: dict) -> dict:
    """Compute percentage improvement for each PPA metric.

    Positive = improvement (reduction), negative = regression (increase).
    """
    deltas = {}
    for key in ["cells", "ffs", "wires"]:
        base_val = baseline.get(key, 0)
        sol_val = solution_metrics.get(key, 0)
        if base_val > 0:
            deltas[f"delta_{key}_pct"] = round((sol_val - base_val) / base_val * 100, 2)
            # deltas[f"delta_{key}_pct"] = round((base_val - sol_val) / base_val * 100, 2)
        else:
            deltas[f"delta_{key}_pct"] = 0.0
    return deltas


def evaluate_task(task_dir: str, solution_file: str, verbose: bool = False) -> dict:
    """Full evaluation pipeline for a single task + solution.

    Returns a result dict with:
        task_id, correct, sim_output (if failed),
        cells, ffs, wires, delta_cells_pct, delta_ffs_pct, delta_wires_pct
    """
    task = load_task(task_dir)

    if not os.path.isfile(solution_file):
        return {
            "task_id": task["task_id"],
            "correct": False,
            "error": f"Solution file not found: {solution_file}",
        }

    if verbose:
        print(f"=== Evaluating {os.path.basename(solution_file)} for {task['task_id']} ===")
        print(f"Top module: {task['top_module']}")
        b = task["baseline"]
        print(f"Baseline: cells={b['cells']}, ffs={b['ffs']}, wires={b['wires']}")

    # Step 1: Correctness
    if verbose:
        print("\n--- Step 1: Simulation ---")

    sim_result = simulate(solution_file, task["testbench"])

    if verbose:
        print(sim_result["output"][:500])

    if not sim_result["pass"]:
        if verbose:
            print(f"\nRESULT: INCORRECT at {sim_result['stage']} stage — skipping synthesis")
        return {
            "task_id": task["task_id"],
            "correct": False,
            "stage": sim_result["stage"],
            "sim_output": sim_result["output"][:1000],
        }

    # Step 2: Synthesis
    if verbose:
        print("\n--- Step 2: Synthesis ---")

    synth_result = synthesize(solution_file, task["top_module"])

    if "error" in synth_result:
        if verbose:
            print(f"Synthesis error: {synth_result['error']}")
        return {
            "task_id": task["task_id"],
            "correct": True,
            "error": synth_result["error"],
        }

    if verbose:
        print(f"Cells: {synth_result['cells']}, FFs: {synth_result['ffs']}, Wires: {synth_result['wires']}")

    # Step 3: Deltas
    deltas = compute_deltas(task["baseline"], synth_result)

    if verbose:
        b = task["baseline"]
        print(f"\n--- Results ---")
        for metric in ["cells", "ffs", "wires"]:
            d = deltas[f"delta_{metric}_pct"]
            label = "reduction" if d >= 0 else "increase"
            print(f"  {metric}: {b[metric]} -> {synth_result[metric]}  ({d}% {label})")

    return {
        "task_id": task["task_id"],
        "correct": True,
        "cells": synth_result["cells"],
        "ffs": synth_result["ffs"],
        "wires": synth_result["wires"],
        **deltas,
    }


def evaluate_all(tasks_dir: str, solutions_dir: str, verbose: bool = False) -> list:
    """Evaluate all solutions found in solutions_dir against their tasks.

    Expects solution files named <task_id>.v (e.g., task_01.v).
    """
    results = []

    task_dirs = sorted([
        d for d in os.listdir(tasks_dir)
        if os.path.isdir(os.path.join(tasks_dir, d)) and d.startswith("task_")
    ])

    for task_id in task_dirs:
        task_dir = os.path.join(tasks_dir, task_id)
        solution_file = os.path.join(solutions_dir, f"{task_id}.v")

        if not os.path.isfile(solution_file):
            if verbose:
                print(f"[{task_id}] No solution found at {solution_file} — skipping")
            continue

        result = evaluate_task(task_dir, solution_file, verbose=verbose)
        results.append(result)

        if verbose:
            print()

    return results


def print_summary_table(results: list):
    """Print a compact summary table of evaluation results."""
    print()
    print(f"{'Task':<10} {'Correct':<9} {'Cells':>7} {'FFs':>5} {'Wires':>7}   {'ΔCells%':>8} {'ΔFFs%':>7} {'ΔWires%':>8}")
    print("-" * 75)

    for r in results:
        if not r.get("correct"):
            reason = r.get("stage", r.get("error", "?"))[:20]
            print(f"{r['task_id']:<10} {'FAIL':<9} {'—':>7} {'—':>5} {'—':>7}   {reason}")
        else:
            print(
                f"{r['task_id']:<10} {'PASS':<9} "
                f"{r.get('cells', '?'):>7} {r.get('ffs', '?'):>5} {r.get('wires', '?'):>7}   "
                f"{r.get('delta_cells_pct', '?'):>8} {r.get('delta_ffs_pct', '?'):>7} {r.get('delta_wires_pct', '?'):>8}"
            )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="PPA Optimization Benchmark — Evaluation Harness"
    )

    # Mode: single task or all tasks
    parser.add_argument("--task", help="Path to task directory (e.g., benchmark/tasks/task_01)")
    parser.add_argument("--solution", help="Path to solution .v file")
    parser.add_argument("--all", action="store_true", help="Evaluate all tasks")
    parser.add_argument(
        "--tasks-dir", default="/workspace/benchmark/tasks",
        help="Directory containing task_XX folders (default: /workspace/benchmark/tasks)"
    )
    parser.add_argument(
        "--solutions-dir",
        help="Directory containing solution files named task_XX.v"
    )
    parser.add_argument("--output", "-o", help="Write JSON results to file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print detailed output")

    args = parser.parse_args()

    # Validate args
    if args.all:
        if not args.solutions_dir:
            parser.error("--all requires --solutions-dir")
        results = evaluate_all(args.tasks_dir, args.solutions_dir, verbose=args.verbose)
    elif args.task and args.solution:
        result = evaluate_task(args.task, args.solution, verbose=args.verbose)
        results = [result]
    else:
        parser.error("Provide either (--task + --solution) or (--all + --solutions-dir)")

    # Summary table
    print_summary_table(results)

    # JSON output
    if args.output:
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults saved to {args.output}")
    else:
        print("\n" + json.dumps(results, indent=2))

    # Exit code: 0 if all correct, 1 if any failed
    all_correct = all(r.get("correct") for r in results)
    sys.exit(0 if all_correct else 1)


if __name__ == "__main__":
    main()
