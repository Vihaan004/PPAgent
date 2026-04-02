# Task 02: Reduce Area of Pipelined Multiplier

## Module
`picorv32_pcpi_fast_mul` (96 lines)

## Optimization Goal
`minimize_area`

## Difficulty
Medium

## Description
The pipelined fast multiplier uses the Verilog `*` operator on **33-bit signed operands** (`$signed(rs1) * $signed(rs2)`, where rs1/rs2 are `reg [32:0]`). Yosys synthesizes this into a large combinational multiplier tree — approximately 7000 cells of combinational logic.

The 33rd bit exists solely for sign extension to handle `mulh` (signed x signed), `mulhsu` (signed x unsigned), and `mulhu` (unsigned x unsigned). For `mul` and `mulhu`, both operands are zero-extended and the extra bit is wasted.

## Constraints
- Must produce identical results for all 4 multiply variants
- Must maintain the PCPI interface protocol
- Pipeline latency (2-3 cycles) should be preserved or reduced
- Do NOT convert back to a multi-cycle shift-add design (that's task_01)
