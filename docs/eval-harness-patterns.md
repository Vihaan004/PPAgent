# Evaluation Harness Patterns

## The Two-Check Pipeline

Every evaluation in this project runs two checks in sequence:

```
Optimized RTL
    |
    v
[1] iverilog + vvp  -->  PASS / FAIL  (correctness)
    |
    v  (only if PASS)
[2] yosys synth + stat  -->  cell_count, ff_count, wire_count  (PPA)
    |
    v
Compare against baseline_metrics.json  -->  delta %
```

**If step 1 fails, step 2 is skipped.** A broken design has no meaningful PPA.

---

## Shell Commands for the Pipeline

```bash
# --- Step 1: Correctness ---
iverilog -o sim.vvp optimized.v testbench.v
if ! vvp sim.vvp 2>&1 | tee sim.log | grep -qiE "error|fail|timeout"; then
    echo "CORRECT"
else
    echo "BROKEN" && exit 1
fi

# --- Step 2: PPA Metrics ---
yosys -qp "read_verilog optimized.v; synth -top MODULE_NAME; stat" 2>&1 | tee synth.log

# Parse metrics
CELLS=$(grep "Number of cells:" synth.log | awk '{print $NF}')
FFS=$(grep -c '$_DFF_' synth.log)  # or sum the counts
WIRES=$(grep "Number of wire bits:" synth.log | awk '{print $NF}')

echo "cells=$CELLS ffs=$FFS wires=$WIRES"
```

---

## Python Skeleton (for harness/evaluate.py)

```python
import subprocess
import json
import tempfile
import os

def simulate(verilog_file: str, testbench_file: str) -> dict:
    """Run iverilog + vvp. Returns {"pass": bool, "output": str}."""
    with tempfile.NamedTemporaryFile(suffix=".vvp", delete=False) as f:
        vvp_path = f.name

    # Compile
    result = subprocess.run(
        ["iverilog", "-o", vvp_path, verilog_file, testbench_file],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return {"pass": False, "output": result.stderr}

    # Simulate
    result = subprocess.run(
        ["vvp", vvp_path],
        capture_output=True, text=True, timeout=60
    )
    output = result.stdout + result.stderr
    passed = not any(kw in output.lower() for kw in ["error", "fail", "timeout"])
    return {"pass": passed, "output": output}


def synthesize(verilog_file: str, top_module: str) -> dict:
    """Run Yosys synthesis. Returns {"cells": int, "ffs": int, "wires": int}."""
    cmd = f"read_verilog {verilog_file}; synth -top {top_module}; stat"
    result = subprocess.run(
        ["yosys", "-qp", cmd],
        capture_output=True, text=True
    )
    output = result.stdout + result.stderr
    
    metrics = {}
    for line in output.split("\n"):
        if "Number of cells:" in line:
            metrics["cells"] = int(line.strip().split()[-1])
        if "Number of wire bits:" in line:
            metrics["wires"] = int(line.strip().split()[-1])
    
    # Count flip-flops
    ff_count = sum(
        int(line.strip().split()[-1])
        for line in output.split("\n")
        if "$_DFF_" in line
    )
    metrics["ffs"] = ff_count
    return metrics


def evaluate_task(original_v, optimized_v, testbench_v, top_module, baseline):
    """Full evaluation: correctness + PPA delta."""
    # Correctness
    sim = simulate(optimized_v, testbench_v)
    if not sim["pass"]:
        return {"correct": False, "error": sim["output"], "ppa_delta": None}

    # PPA
    metrics = synthesize(optimized_v, top_module)
    delta = {
        k: round((baseline[k] - metrics[k]) / baseline[k] * 100, 2)
        for k in ["cells", "ffs", "wires"]
    }
    return {"correct": True, "metrics": metrics, "ppa_delta_pct": delta}
```

---

## baseline_metrics.json Format

```json
{
    "top_module": "picorv32_pcpi_mul",
    "cells": 1842,
    "ffs": 128,
    "wires": 2156
}
```

Generate baselines by running `synthesize()` on the original unmodified RTL.

---

## Tips

- **Timeout**: Always set a timeout on `vvp` (60s is generous). Buggy RTL can hang forever.
- **Determinism**: Yosys synthesis is deterministic for the same input + version. Metrics will be reproducible.
- **Multiple modules in one file**: If your optimized file still contains all picorv32 modules, Yosys `-top` selects the right one.
- **Temp files**: Use `tempfile` for intermediate `.vvp` files to avoid clutter.
