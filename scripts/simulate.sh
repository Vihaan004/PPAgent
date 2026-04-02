#!/bin/bash
# Run iverilog + vvp simulation for a Verilog file against a testbench.
# Must be run INSIDE the Docker container (or call via docker_run.sh).
#
# Usage:
#   ./scripts/simulate.sh <verilog_file> <testbench_file>
#   ./scripts/simulate.sh benchmark/tasks/task_01/original.v benchmark/tasks/task_01/testbench.v
#
# Exit code 0 = PASS, 1 = FAIL/ERROR
# Outputs simulation log to stdout.

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <verilog_file> <testbench_file> [extra_verilog_files...]"
    exit 1
fi

VERILOG_FILE="$1"
TESTBENCH_FILE="$2"
shift 2
EXTRA_FILES="$@"

TMPDIR=$(mktemp -d)
VVP_FILE="$TMPDIR/sim.vvp"

# Compile
if ! iverilog -o "$VVP_FILE" "$VERILOG_FILE" "$TESTBENCH_FILE" $EXTRA_FILES 2>&1; then
    echo "COMPILE_ERROR"
    rm -rf "$TMPDIR"
    exit 1
fi

# Simulate with 60s timeout
SIM_OUTPUT=$(timeout 60 vvp "$VVP_FILE" 2>&1) || {
    echo "$SIM_OUTPUT"
    echo "TIMEOUT_OR_ERROR"
    rm -rf "$TMPDIR"
    exit 1
}

echo "$SIM_OUTPUT"
rm -rf "$TMPDIR"

# Check for failure keywords
if echo "$SIM_OUTPUT" | grep -qiE "FAIL|ERROR|TIMEOUT"; then
    exit 1
fi

exit 0
