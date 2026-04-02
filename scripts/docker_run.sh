#!/bin/bash
# Wrapper to run any command inside the ppagent-env Docker container.
# Usage:
#   ./scripts/docker_run.sh <command>
#   ./scripts/docker_run.sh bash                      # interactive shell
#   ./scripts/docker_run.sh python3 harness/evaluate.py task_01
#
# Automatically mounts the project root to /workspace.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

docker run --rm -it \
    -v "$PROJECT_ROOT:/workspace" \
    -w /workspace \
    ppagent-env \
    "$@"
