# Subtask 1 Plan — 5 PPA Optimization Benchmark Tasks

## Context

Build a PPA optimization benchmark for picorv32. Each task pairs an original Verilog module with a self-contained testbench and baseline synthesis metrics. An LLM agent (Subtask 3) will later attempt to optimize these. Evaluation harness is separate — this plan covers task creation only.

## Baseline Synthesis Data (Yosys 0.9, generic cells)

| Module | Cells | FFs | Wire Bits |
|--------|-------|-----|-----------|
| `picorv32` (full core) | 9602 | 1614 | 10136 |
| `picorv32_pcpi_mul` | 1471 | 304 | — |
| `picorv32_pcpi_fast_mul` | 7185 | 133 | 7287 |
| `picorv32_pcpi_div` | 1682 | 200 | 1782 |
| `picorv32_regs` | 3983 | 992 | 4035 |

---

## Task Definitions

### Task 01 — Reduce Area of Shift-Add Multiplier
- **Module**: `picorv32_pcpi_mul` (lines 2197-2316, 120 lines)
- **Goal**: `minimize_area` | **Difficulty**: Easy
- **Optimization**: Replace carry-save accumulator (64-bit `rd`, `rdx`, nested carry-chain loop) with simpler `rd += (rs1[0] ? rs2 : 0)` shift-add. Eliminates `rdx` register (64 FFs) and carry-save tree.
- **Expected**: ~30-40% cell reduction, ~20% FF reduction
- **Testbench**: PCPI interface, ~24 vectors for mul/mulh/mulhsu/mulhu with edge cases

### Task 02 — Reduce Area of Pipelined Multiplier
- **Module**: `picorv32_pcpi_fast_mul` (lines 2318-2413, 96 lines)
- **Goal**: `minimize_area` | **Difficulty**: Medium
- **Optimization**: Reduce 33→32-bit operand width for unsigned variants. Remove dead pipeline registers at default params. Simplify output mux.
- **Expected**: ~10-15% cell reduction
- **Testbench**: Same PCPI vectors as Task 01, verify 2-4 cycle completion

### Task 03 — Reduce FF Count of Divider (Power)
- **Module**: `picorv32_pcpi_div` (lines 2420-2510, 91 lines)
- **Goal**: `minimize_power` | **Difficulty**: Medium
- **Optimization**: Replace 63-bit `divisor` shift register with 32-bit stored + 5-bit counter (save 31 FFs). Replace 32-bit one-hot `quotient_msk` with counter-indexed bit-set (save 32 FFs).
- **Expected**: ~30% FF reduction
- **Testbench**: PCPI interface, ~24 vectors for div/divu/rem/remu incl. div-by-zero, MIN_INT/-1

### Task 04 — Improve Shift Performance in Main Core
- **Module**: `picorv32` (full core, 2112 lines, target: `cpu_state_shift` FSM state)
- **Goal**: `minimize_timing` | **Difficulty**: Hard
- **Optimization**: Replace shift-by-4/shift-by-1 iteration (10 cycles worst case) with logarithmic shifter (16/8/4/2/1 stages, ≤5 cycles). Must preserve SRA/SRL/SLL + signed handling.
- **Expected**: ~50% fewer shift cycles
- **Testbench**: testbench_ez.v style, hardcoded slli/srli/srai instructions, check results in memory

### Task 05 — Strip Unused Features from Main Core
- **Module**: `picorv32` (full core, 2112 lines)
- **Goal**: `minimize_area` | **Difficulty**: Easy-Medium
- **Optimization**: Hardcode ENABLE_COUNTERS=0, ENABLE_COUNTERS64=0, CATCH_MISALIGN=0, CATCH_ILLINSN=0, ENABLE_TRACE=0. Inline values, remove dead logic and signals.
- **Expected**: ~15-25% cell reduction, ~8-15% FF reduction
- **Testbench**: testbench_ez.v style, basic instruction loop (no CSR instructions)

---

## Implementation Steps

For each task, create `benchmark/tasks/task_XX/`:

| File | Content |
|------|---------|
| `original.v` | Extracted module (tasks 01-03) or full picorv32.v (tasks 04-05) |
| `testbench.v` | Self-contained, no firmware deps |
| `baseline_metrics.json` | `{ "top_module", "cells", "ffs", "wires" }` from Yosys |
| `description.md` | Task spec: goal, hints, constraints |

### Build order
1. Create directory structure
2. Extract modules into `original.v` files
3. Write testbenches (PCPI-driven for 01-03, testbench_ez-style for 04-05)
4. Verify all testbenches pass against originals (iverilog + vvp in Docker)
5. Generate baseline_metrics.json for each task (Yosys in Docker)
6. Write description.md for each task

### Verification (all inside Docker)
```bash
for t in 01 02 03 04 05; do
  cd /workspace/benchmark/tasks/task_$t
  iverilog -o sim.vvp original.v testbench.v && vvp sim.vvp  # must PASS
done
```

---

## Files Involved
- **Source**: `picorv32/picorv32.v` (extract modules)
- **Template**: `picorv32/testbench_ez.v` (adapt for tasks 04-05)
- **Output**: `benchmark/tasks/task_{01..05}/`
