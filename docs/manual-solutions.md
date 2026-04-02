# Manual Solutions (Subtask 2)

Three of five benchmark tasks were manually optimized to validate the evaluation harness and establish human baselines. Tasks 02 (medium) and 04 (hard) were reserved for the LLM agent.

## Results

| Task | Module | Goal | Cells | FFs | Wires |
|------|--------|------|-------|-----|-------|
| 01 | `pcpi_mul` | area | **-12.6%** | -21.1% | -26.1% |
| 03 | `pcpi_div` | power (FFs) | +1.0% | **-28.5%** | +4.6% |
| 05 | `picorv32` | area | **-13.0%** | -8.8% | -12.3% |

---

## Task 01 — Shift-Add Multiplier (1516 -> 1325 cells)

**Change**: Replaced carry-save accumulator (CSA) with a simple shift-add loop.

The original uses two 64-bit registers (`rd`, `rdx`) plus a segmented carry-chain adder to accumulate partial products without carry propagation. This reduces critical path at the cost of doubled register width and complex combinational logic.

The optimized version uses a single 64-bit accumulator: `rd <= rd + (rs1[0] ? rs2 : 0)`. This eliminates `rdx` (64 FFs), the `next_rdx`/`next_rdt` wires, and the entire carry-chain loop. Cycle count is unchanged (32 for `mul`, 64 for `mulh`). The adder is wider but synthesizes to fewer cells because Yosys handles a simple add more efficiently than the CSA tree.

**Tradeoff**: Slightly longer critical path per cycle (full 64-bit ripple-carry vs segmented CSA), but area is the optimization target here.

## Task 03 — Counter-Based Divider (200 -> 143 FFs)

**Change**: Replaced shift registers with a 6-bit iteration counter.

The original stores a 63-bit `divisor` (initialized as `rs2 << 31`, shifted right each cycle) and a 32-bit one-hot `quotient_msk` (shifted right each cycle). Both are functionally counters encoded as shift registers.

The optimized version stores only the 32-bit `divisor_stored` and a 6-bit `bit_idx` (31 down to 0). The shifted divisor is computed combinationally: `{32'b0, divisor_stored} << bit_idx[4:0]`. Quotient bits are set by index: `quotient[bit_idx] <= 1`. This eliminates 57 FFs (31 from divisor, 27 from quotient_msk, minus 6 for the counter).

**Tradeoff**: The combinational barrel shifter adds ~17 cells (+1%), but the goal is FF reduction (power proxy), which improved by 28.5%.

## Task 05 — Feature Stripping (9602 -> 8350 cells)

**Change**: Disabled and removed code for four optional features.

| Feature | What was removed | Savings |
|---------|-----------------|---------|
| `ENABLE_COUNTERS=0` | 128-bit `count_cycle`/`count_instr` registers, CSR decode (`rdcycle` etc.), counter-read mux | ~128 FFs, CSR logic |
| `ENABLE_COUNTERS64=0` | Upper 32-bit masking (dead with counters off) | Minor |
| `CATCH_MISALIGN=0` | Word/halfword alignment checks, instruction PC alignment check, bus error trap paths | Comparators + muxes |
| `CATCH_ILLINSN=0` | Illegal instruction detection logic (kept `ebreak` trap via inverse-condition path) | Decoder logic |
| `ENABLE_TRACE=0` | `trace_valid`/`trace_data` generation in fetch, stmem, ldmem states | ~36-bit trace regs + muxes |

Parameter defaults were changed to 0 so synthesis uses the stripped configuration. The testbench already instantiates with `ENABLE_COUNTERS=0` and `ENABLE_IRQ=0`, so simulation is unaffected. Dead code was manually removed rather than relying on synthesis `opt` passes, which don't always eliminate parameterized branches completely.

**Constraint preserved**: `ebreak` still traps correctly via the `!CATCH_ILLINSN` fallback path (`decoder_trigger_q && instr_ecall_ebreak`).
