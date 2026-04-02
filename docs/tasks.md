## Subtasks — Detailed Breakdown

### Subtask 1: Benchmark Construction

**Goal**: Extract ≥5 self-contained optimization tasks from picorv32 and build 
an automated evaluation harness.

**Finding tasks**:
- Read `picorv32.v` carefully. Look for: redundant logic, wide muxes with 
  overlapping cases, deeply nested conditionals, unoptimized state encodings, 
  repeated bit manipulations, unnecessary intermediate signals.
- Carve each target out into its own `task_XX/original.v` — either as an 
  isolated module or a clearly scoped always-block extracted into a wrapper.
- Document WHY each is suboptimal and WHAT metric it targets (area vs timing).

**Building the harness** (`harness/evaluate.py`):
- `get_baseline(task_id)` → run Yosys `synth + stat` on `original.v`, 
  parse and store cell count, FF count, wire count to `baseline_metrics.json`
- `evaluate(task_id, candidate_verilog)` →
  1. Write candidate to temp file
  2. Run `iverilog` + `vvp` with task testbench → parse pass/fail + errors
  3. Run Yosys → parse new metrics
  4. Return `{ correct: bool, errors: str, delta_cells: %, delta_ff: % }`
- All results logged to `results/eval_log.json`

**Testbenches**: Where possible, adapt picorv32's existing testbench scoped 
to the module under test. For isolated modules, write a simple directed 
testbench that covers all input combinations or key functional scenarios.

---

### Subtask 2: Manual Optimization

**Goal**: Hand-optimize 2-3 tasks and validate the harness produces sensible output.

- Pick the 2-3 tasks with the most obvious optimization opportunities.
- Edit the RTL by hand, save to `solutions/manual/task_XX_manual.v`.
- Run through `evaluate.py` — confirm correctness passes and metrics improve.
- This validates your harness AND gives you a human-baseline for Subtask 4.
- Document your reasoning for each change in `solutions/manual/task_XX_notes.md`.

---

### Subtask 3: LLM Optimization Agent

**Goal**: Build a ReAct-style agent that iteratively rewrites RTL using 
tool feedback to improve PPA without breaking correctness.

**Agent loop** (`agent/optimizer_agent.py`):
```
for each task:
  context = task description + original RTL + baseline metrics
  for up to N iterations:
    llm_response = call_openai(context + history)  # proposes rewrite
    result = evaluate(task_id, llm_response.new_rtl)
    if result.correct and result.delta_cells < best_so_far:
      best = result
    history.append(result)  # feed errors + metrics back
  save best correct solution to solutions/agent/task_XX_agent.v
```

**Tools exposed to the agent** (as OpenAI function calls):
- `simulate(verilog_code)` → `{ passed: bool, errors: str }`
- `synthesize(verilog_code)` → `{ cells: int, ffs: int, wires: int }`

**Prompting strategy**:
- System prompt: RTL optimization expert, minimize cell count, must preserve 
  functional behavior, explain changes before rewriting.
- On each iteration: include current metrics, previous attempt errors, 
  and delta from baseline so the agent can self-correct.

---

### Subtask 4: Evaluation + Analysis

**Goal**: Benchmark the agent against baselines, understand failure modes, iterate.

**Baselines**:
- **Zero-shot**: single LLM call per task, no feedback loop
- **Manual**: your Subtask 2 solutions
- **Yosys-native**: run `opt; opt_clean; abc` passes on original — 
  this is the non-LLM automated ceiling

**Output**: a results table across all tasks and all methods:
```
| Task | Baseline | Yosys-opt | Zero-shot | Agent | Agent Correct? |
```

**Analysis**: identify WHY the agent succeeds or fails per task — 
syntax errors, semantically correct but no PPA gain, overcomplicated rewrites, 
etc. Use this to justify any agent design changes you make.