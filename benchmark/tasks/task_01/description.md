# Task 01: Reduce Area of Shift-Add Multiplier

## Module
`picorv32_pcpi_mul` (120 lines)

## Optimization Goal
`minimize_area`

## Difficulty
Easy

## Description
The multi-cycle multiplier implements RISC-V M-extension multiply instructions (mul, mulh, mulhsu, mulhu) using a **carry-save accumulator (CSA)** architecture. The CSA uses 64-bit `rd` and `rdx` registers with a nested carry-chain loop to accumulate partial products.

While the CSA reduces critical path delay in the adder, it comes at significant area cost:
- Two 64-bit accumulator registers (`rd`, `rdx`) = 128 FFs
- Six 64-bit combinational wires (`next_rd`, `next_rdx`, `next_rdt`, `next_rs1`, `next_rs2`, `this_rs2`)
- A nested loop generating carry-save logic (`CARRY_CHAIN`-wide segmented adder)

## Constraints
- Must produce identical results for all 4 multiply variants (mul, mulh, mulhsu, mulhu)
- Must maintain the PCPI interface protocol (pcpi_valid/ready/wait/wr handshake)
- Latency may change but correctness must be preserved

