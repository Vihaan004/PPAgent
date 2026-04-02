#!/bin/bash
# Generate Yosys-only optimized baseline for a task (Subtask 4 comparison).
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/yosys_opt_baseline.sh <task_dir>
#   ./scripts/yosys_opt_baseline.sh benchmark/tasks/task_01
#
# Runs extra Yosys optimization passes on the original and saves
# the optimized netlist + metrics.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <task_dir>"
    exit 1
fi

TASK_DIR="$1"
ORIGINAL="$TASK_DIR/original.v"
BASELINE="$TASK_DIR/baseline_metrics.json"

if [ ! -f "$ORIGINAL" ]; then echo "ERROR: original.v not found"; exit 1; fi
if [ ! -f "$BASELINE" ]; then echo "ERROR: baseline_metrics.json not found"; exit 1; fi

TOP_MODULE=$(grep '"top_module"' "$BASELINE" | sed 's/.*: *"\(.*\)".*/\1/')
TASK_ID=$(basename "$TASK_DIR")
OUT_DIR="/workspace/benchmark/solutions/yosys_opt"
mkdir -p "$OUT_DIR"

LOG_FILE="/tmp/yosys_opt_${TASK_ID}.log"

# Run synthesis with extra optimization passes (same default gate library as baseline)
yosys -p "
    read_verilog $ORIGINAL;
    synth -top $TOP_MODULE;
    opt -full;
    opt_clean -purge;
    opt -full;
    opt_clean -purge;
    stat;
    write_verilog $OUT_DIR/${TASK_ID}.v;
" > "$LOG_FILE" 2>&1

# Extract metrics
CELLS=$(grep "Number of cells:" "$LOG_FILE" | tail -1 | awk '{print $NF}')
WIRES=$(grep "Number of wire bits:" "$LOG_FILE" | tail -1 | awk '{print $NF}')
TOTAL_LINES=$(wc -l < "$LOG_FILE")
LAST_STAT=$(grep -n "Printing statistics" "$LOG_FILE" | tail -1 | cut -d: -f1)
FFS=$(tail -n +${LAST_STAT:-1} "$LOG_FILE" | grep "_DFF_" | awk '{sum += $NF} END {print sum+0}')

BASE_CELLS=$(grep '"cells"' "$BASELINE" | sed 's/[^0-9]//g')
DELTA=$(python3 -c "print(round(($BASE_CELLS - $CELLS) / $BASE_CELLS * 100, 2))")

# Save metrics JSON alongside the netlist
cat > "$OUT_DIR/${TASK_ID}_metrics.json" <<EOFJ
{
    "top_module": "${TOP_MODULE}",
    "cells": ${CELLS},
    "ffs": ${FFS},
    "wires": ${WIRES}
}
EOFJ

echo "=== Yosys-opt baseline for $TASK_ID ==="
echo "Module: $TOP_MODULE"
if python3 -c "exit(0 if $DELTA >= 0 else 1)" 2>/dev/null; then
    LABEL="reduction"
else
    LABEL="increase"
fi
echo "Cells: $BASE_CELLS -> $CELLS  (${DELTA}% ${LABEL})"
echo "FFs: $FFS"
echo "Wires: $WIRES"
echo "Output: $OUT_DIR/${TASK_ID}.v"
echo "Metrics: $OUT_DIR/${TASK_ID}_metrics.json"
