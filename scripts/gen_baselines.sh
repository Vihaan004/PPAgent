#!/bin/bash
# Regenerate baseline_metrics.json for all benchmark tasks.
# Must be run INSIDE the Docker container.
#
# Usage:
#   ./scripts/gen_baselines.sh
#
# Reads top_module from each existing baseline_metrics.json (or description.md),
# runs Yosys synthesis, and writes updated metrics.

set -e

TASKS_DIR="/workspace/benchmark/tasks"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for task_dir in "$TASKS_DIR"/task_*; do
    task_name=$(basename "$task_dir")

    if [ ! -f "$task_dir/original.v" ]; then
        echo "[$task_name] SKIP — no original.v"
        continue
    fi

    # Get top_module from existing baseline or infer from task
    if [ -f "$task_dir/baseline_metrics.json" ]; then
        TOP_MODULE=$(grep '"top_module"' "$task_dir/baseline_metrics.json" | sed 's/.*: *"\(.*\)".*/\1/')
    else
        echo "[$task_name] SKIP — no baseline_metrics.json (don't know top_module)"
        continue
    fi

    echo -n "[$task_name] Synthesizing $TOP_MODULE... "

    METRICS=$("$SCRIPT_DIR/synthesize.sh" "$task_dir/original.v" "$TOP_MODULE")
    echo "$METRICS" > "$task_dir/baseline_metrics.json"

    echo "done"
    echo "  $METRICS"
done
