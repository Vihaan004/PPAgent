#!/bin/bash
# Validate all benchmark tasks: compile + simulate testbenches against originals.
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/validate_all.sh
#
# Runs every task's testbench against its original.v and reports pass/fail.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TASKS_DIR="/workspace/benchmark/tasks"
PASS=0
FAIL=0

for task_dir in "$TASKS_DIR"/task_*; do
    task_name=$(basename "$task_dir")

    if [ ! -f "$task_dir/original.v" ] || [ ! -f "$task_dir/testbench.v" ]; then
        echo "[$task_name] SKIP — missing original.v or testbench.v"
        continue
    fi

    echo "--- $task_name ---"

    TMPVVP=$(mktemp /tmp/sim_XXXXXX.vvp)

    # Compile
    if ! iverilog -o "$TMPVVP" "$task_dir/original.v" "$task_dir/testbench.v" 2>&1; then
        echo "[$task_name] COMPILE_ERROR"
        FAIL=$((FAIL + 1))
        rm -f "$TMPVVP"
        continue
    fi

    # Simulate
    OUTPUT=$(timeout 60 vvp "$TMPVVP" 2>&1) || true
    rm -f "$TMPVVP"

    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "ALL TESTS PASSED"; then
        PASS=$((PASS + 1))
    else
        echo "[$task_name] FAILED"
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

echo "=========================================="
echo "  Validation: $PASS passed, $FAIL failed"
echo "=========================================="

[ $FAIL -eq 0 ] && exit 0 || exit 1
