#!/bin/bash
# Run Yosys synthesis and extract PPA metrics.
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/synthesize.sh <verilog_file> <top_module>
#   ./scripts/synthesize.sh benchmark/tasks/task_01/original.v picorv32_pcpi_mul
#
# Output: JSON to stdout with cells, ffs, wires fields.
# Also saves full synthesis log to /tmp/synth_<top_module>.log

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <verilog_file> <top_module>"
    exit 1
fi

VERILOG_FILE="$1"
TOP_MODULE="$2"
LOG_FILE="/tmp/synth_${TOP_MODULE}.log"

# Run synthesis
yosys -p "read_verilog $VERILOG_FILE; synth -top $TOP_MODULE; stat" > "$LOG_FILE" 2>&1

# Extract metrics from the final stat block
CELLS=$(grep "Number of cells:" "$LOG_FILE" | tail -1 | awk '{print $NF}')
WIRES=$(grep "Number of wire bits:" "$LOG_FILE" | tail -1 | awk '{print $NF}')

# Sum all DFF variants (only from the last stat block)
TOTAL_LINES=$(wc -l < "$LOG_FILE")
LAST_STAT=$(grep -n "Printing statistics" "$LOG_FILE" | tail -1 | cut -d: -f1)
FFS=$(tail -n +${LAST_STAT:-1} "$LOG_FILE" | grep "_DFF_" | awk '{sum += $NF} END {print sum+0}')

echo "{"
echo "    \"top_module\": \"${TOP_MODULE}\","
echo "    \"cells\": ${CELLS:-0},"
echo "    \"ffs\": ${FFS:-0},"
echo "    \"wires\": ${WIRES:-0}"
echo "}"
