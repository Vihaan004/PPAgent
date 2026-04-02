# Task 05: Strip Unused Features from Main Core (Area Reduction)

## Module
`picorv32` (full core, 3049 lines)

## Optimization Goal
`minimize_area`

## Difficulty
Easy-Medium

## Description
The picorv32 core is highly parameterized with many optional features enabled by default. Several of these features add significant logic that may not be needed for a minimal RV32I configuration:

- **`ENABLE_COUNTERS=1`** + **`ENABLE_COUNTERS64=1`**: Adds two 64-bit counters (`count_cycle`, `count_instr`) = 128 FFs, plus CSR instruction decode logic (`rdcycle`, `rdcycleh`, `rdinstr`, `rdinstrh`) and the counter-read mux in the ALU output path.
- **`CATCH_MISALIGN=1`**: Adds misaligned address detection comparators and trap logic.
- **`CATCH_ILLINSN=1`**: Adds illegal instruction detection and trap logic.
- **`ENABLE_TRACE=0`** (already off by default, but trace signal generation still exists).


## Constraints
- The optimized core must still execute RV32I base instructions correctly
- Do NOT use CSR instructions (`rdcycle`, `rdinstr`, etc.) in testing — they are removed
- Memory interface behavior must be identical
- Trap on `ebreak` should still work (it's independent of `CATCH_ILLINSN`)
- Do NOT disable `ENABLE_REGS_16_31` or `ENABLE_REGS_DUALPORT` — register file must remain full
