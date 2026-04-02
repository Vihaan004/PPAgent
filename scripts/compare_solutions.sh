#!/bin/bash
# Compare multiple solutions for a task side-by-side.
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/compare_solutions.sh <task_id>
#   ./scripts/compare_solutions.sh task_01
#
# Looks for solutions in:
#   benchmark/solutions/manual/<task_id>.v
#   benchmark/solutions/agent/<task_id>.v
#   benchmark/tasks/<task_id>/original.v  (baseline)
#
# Outputs a comparison table.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <task_id>"
    exit 1
fi

TASK_ID="$1"
TASK_DIR="/workspace/benchmark/tasks/$TASK_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$TASK_DIR/baseline_metrics.json" ]; then
    echo "ERROR: No baseline for $TASK_ID"
    exit 1
fi

TOP_MODULE=$(grep '"top_module"' "$TASK_DIR/baseline_metrics.json" | sed 's/.*: *"\(.*\)".*/\1/')
BASE_CELLS=$(grep '"cells"' "$TASK_DIR/baseline_metrics.json" | sed 's/[^0-9]//g')
BASE_FFS=$(grep '"ffs"' "$TASK_DIR/baseline_metrics.json" | sed 's/[^0-9]//g')

echo "=== $TASK_ID: $TOP_MODULE ==="
printf "%-15s %8s %8s %10s %10s\n" "Solution" "Cells" "FFs" "ΔCells%" "ΔFFs%"
printf "%-15s %8s %8s %10s %10s\n" "--------" "-----" "---" "-------" "-----"
printf "%-15s %8s %8s %10s %10s\n" "baseline" "$BASE_CELLS" "$BASE_FFS" "0.00" "0.00"

for solution_type in manual agent yosys_opt; do
    SOL_FILE="/workspace/benchmark/solutions/$solution_type/${TASK_ID}.v"
    METRICS_FILE="/workspace/benchmark/solutions/$solution_type/${TASK_ID}_metrics.json"

    # yosys_opt produces gate-level netlists that can't be re-simulated.
    # Read pre-computed metrics from the JSON file instead.
    if [ "$solution_type" = "yosys_opt" ]; then
        if [ ! -f "$METRICS_FILE" ]; then
            continue
        fi
        SOL_CELLS=$(grep '"cells"' "$METRICS_FILE" | sed 's/[^0-9]//g')
        SOL_FFS=$(grep '"ffs"' "$METRICS_FILE" | sed 's/[^0-9]//g')

        DC=$(python3 -c "print(round(($BASE_CELLS - $SOL_CELLS) / $BASE_CELLS * 100, 2))")
        DF=$(python3 -c "print(round(($BASE_FFS - $SOL_FFS) / $BASE_FFS * 100, 2) if $BASE_FFS > 0 else 0.0)")

        printf "%-15s %8s %8s %10s %10s  %s\n" "$solution_type" "$SOL_CELLS" "$SOL_FFS" "$DC" "$DF" "(synth-only)"
        continue
    fi

    if [ ! -f "$SOL_FILE" ]; then
        continue
    fi

    # Check correctness via simulation
    TMPVVP=$(mktemp /tmp/sim_XXXXXX.vvp)
    CORRECT="false"
    if iverilog -o "$TMPVVP" "$SOL_FILE" "$TASK_DIR/testbench.v" 2>/dev/null; then
        SIM_OUT=$(timeout 60 vvp "$TMPVVP" 2>&1) || true
        if echo "$SIM_OUT" | grep -q "ALL TESTS PASSED"; then
            CORRECT="true"
        fi
    fi
    rm -f "$TMPVVP"

    if [ "$CORRECT" = "false" ]; then
        printf "%-15s %8s %8s %10s %10s\n" "$solution_type" "FAIL" "FAIL" "-" "-"
        continue
    fi

    # Synthesize
    SYNTH_JSON=$("$SCRIPT_DIR/synthesize.sh" "$SOL_FILE" "$TOP_MODULE" 2>/dev/null)
    SOL_CELLS=$(echo "$SYNTH_JSON" | grep '"cells"' | sed 's/[^0-9]//g')
    SOL_FFS=$(echo "$SYNTH_JSON" | grep '"ffs"' | sed 's/[^0-9]//g')

    DC=$(python3 -c "print(round(($BASE_CELLS - $SOL_CELLS) / $BASE_CELLS * 100, 2))")
    DF=$(python3 -c "print(round(($BASE_FFS - $SOL_FFS) / $BASE_FFS * 100, 2) if $BASE_FFS > 0 else 0.0)")

    printf "%-15s %8s %8s %10s %10s\n" "$solution_type" "$SOL_CELLS" "$SOL_FFS" "$DC" "$DF"
done
