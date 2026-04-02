#!/bin/bash
# Evaluate a candidate solution against a benchmark task.
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/eval_solution.sh <task_dir> <solution_file>
#   ./scripts/eval_solution.sh benchmark/tasks/task_01 benchmark/solutions/manual/task_01.v
#
# Runs: 1) simulation for correctness, 2) synthesis for PPA, 3) delta vs baseline.
# Output: JSON summary to stdout.

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <task_dir> <solution_file>"
    exit 1
fi

TASK_DIR="$1"
SOLUTION_FILE="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TESTBENCH="$TASK_DIR/testbench.v"
BASELINE="$TASK_DIR/baseline_metrics.json"

if [ ! -f "$TESTBENCH" ]; then echo "ERROR: testbench not found at $TESTBENCH"; exit 1; fi
if [ ! -f "$BASELINE" ]; then echo "ERROR: baseline not found at $BASELINE"; exit 1; fi
if [ ! -f "$SOLUTION_FILE" ]; then echo "ERROR: solution not found at $SOLUTION_FILE"; exit 1; fi

TOP_MODULE=$(grep '"top_module"' "$BASELINE" | sed 's/.*: *"\(.*\)".*/\1/')
BASE_CELLS=$(grep '"cells"' "$BASELINE" | sed 's/[^0-9]//g')
BASE_FFS=$(grep '"ffs"' "$BASELINE" | sed 's/[^0-9]//g')
BASE_WIRES=$(grep '"wires"' "$BASELINE" | sed 's/[^0-9]//g')

echo "=== Evaluating $(basename $SOLUTION_FILE) for $(basename $TASK_DIR) ==="
echo "Top module: $TOP_MODULE"
echo "Baseline: cells=$BASE_CELLS, ffs=$BASE_FFS, wires=$BASE_WIRES"
echo ""

# Step 1: Correctness
echo "--- Step 1: Simulation ---"
TMPVVP=$(mktemp /tmp/sim_XXXXXX.vvp)
CORRECT="false"

if iverilog -o "$TMPVVP" "$SOLUTION_FILE" "$TESTBENCH" 2>&1; then
    SIM_OUT=$(timeout 60 vvp "$TMPVVP" 2>&1) || true
    echo "$SIM_OUT"

    if echo "$SIM_OUT" | grep -q "ALL TESTS PASSED"; then
        CORRECT="true"
    fi
else
    echo "COMPILE_ERROR"
fi
rm -f "$TMPVVP"

if [ "$CORRECT" = "false" ]; then
    echo ""
    echo "RESULT: INCORRECT — skipping synthesis"
    echo "{"
    echo "    \"correct\": false,"
    echo "    \"cells\": null,"
    echo "    \"ffs\": null,"
    echo "    \"wires\": null,"
    echo "    \"delta_cells_pct\": null,"
    echo "    \"delta_ffs_pct\": null,"
    echo "    \"delta_wires_pct\": null"
    echo "}"
    exit 1
fi

# Step 2: Synthesis
echo ""
echo "--- Step 2: Synthesis ---"
SYNTH_JSON=$("$SCRIPT_DIR/synthesize.sh" "$SOLUTION_FILE" "$TOP_MODULE")
echo "$SYNTH_JSON"

SOL_CELLS=$(echo "$SYNTH_JSON" | grep '"cells"' | sed 's/[^0-9]//g')
SOL_FFS=$(echo "$SYNTH_JSON" | grep '"ffs"' | sed 's/[^0-9]//g')
SOL_WIRES=$(echo "$SYNTH_JSON" | grep '"wires"' | sed 's/[^0-9]//g')

# Step 3: Compute deltas
DELTA_CELLS=$(python3 -c "print(round(($BASE_CELLS - $SOL_CELLS) / $BASE_CELLS * 100, 2))")
DELTA_FFS=$(python3 -c "print(round(($BASE_FFS - $SOL_FFS) / $BASE_FFS * 100, 2) if $BASE_FFS > 0 else 0.0)")
DELTA_WIRES=$(python3 -c "print(round(($BASE_WIRES - $SOL_WIRES) / $BASE_WIRES * 100, 2))")

label_delta() {
    python3 -c "d=$1; print('reduction' if d >= 0 else 'increase')"
}

echo ""
echo "--- Results ---"
echo "Cells:  $BASE_CELLS -> $SOL_CELLS  (${DELTA_CELLS}% $(label_delta $DELTA_CELLS))"
echo "FFs:    $BASE_FFS -> $SOL_FFS  (${DELTA_FFS}% $(label_delta $DELTA_FFS))"
echo "Wires:  $BASE_WIRES -> $SOL_WIRES  (${DELTA_WIRES}% $(label_delta $DELTA_WIRES))"
echo ""

echo "{"
echo "    \"correct\": true,"
echo "    \"cells\": $SOL_CELLS,"
echo "    \"ffs\": $SOL_FFS,"
echo "    \"wires\": $SOL_WIRES,"
echo "    \"delta_cells_pct\": $DELTA_CELLS,"
echo "    \"delta_ffs_pct\": $DELTA_FFS,"
echo "    \"delta_wires_pct\": $DELTA_WIRES"
echo "}"
