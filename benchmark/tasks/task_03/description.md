# Task 03: Reduce Flip-Flop Count of Divider (Power Optimization)

## Module
`picorv32_pcpi_div` (91 lines)

## Optimization Goal
`minimize_power` (proxy: reduce flip-flop count)

## Difficulty
Medium

## Description
The divider implements RISC-V M-extension division/remainder instructions (div, divu, rem, remu) using a **restoring division algorithm**. It processes one bit per cycle over 32 iterations.

The current implementation uses wide shift registers:
- `divisor` (63 bits): Initialized as `pcpi_rs2 << 31`, shifted right by 1 each cycle
- `quotient_msk` (32 bits): One-hot mask starting at `1 << 31`, shifted right by 1 each cycle
- `dividend` (32 bits): Working dividend, subtracted from when `divisor <= dividend`
- `quotient` (32 bits): Accumulated quotient bits via `quotient | quotient_msk`

Total: 200 FFs. The `divisor` and `quotient_msk` registers are essentially counters encoded as shift registers.

## Constraints
- Must handle all 4 division variants correctly (div, divu, rem, remu)
- Must handle edge cases: division by zero (RISC-V spec: div returns -1, rem returns dividend), signed overflow (MIN_INT / -1 = MIN_INT)
- Sign handling (`outsign`) must be preserved exactly
- Cycle count may change slightly but division must complete

