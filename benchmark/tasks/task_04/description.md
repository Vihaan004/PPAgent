# Task 04: Improve Shift Performance in Main Core

## Module
`picorv32` (full core, 3049 lines — target: `cpu_state_shift` FSM state)

## Optimization Goal
`minimize_timing` (reduce cycle count for shift operations)

## Difficulty
Hard

## Description
With default parameters (`BARREL_SHIFTER=0`, `TWO_STAGE_SHIFT=1`), the shifter operates iteratively in the `cpu_state_shift` FSM state:
- If `reg_sh >= 4`: shift by 4 bits per cycle
- Otherwise: shift by 1 bit per cycle
- Worst case (shift by 31): 7 + 3 = **10 cycles**

A full barrel shifter (`BARREL_SHIFTER=1`) completes in 1 cycle but adds significant area. The goal is to find a middle ground.

## Constraints
- Must correctly handle SLL (shift left logical), SRL (shift right logical), and SRA (shift right arithmetic)
- SRA must sign-extend (the `reg_out` assignment must preserve the sign bit)
- The FSM state transitions must remain consistent — `cpu_state_shift` must still transition to the correct next state when shifting is complete
- Do NOT enable `BARREL_SHIFTER` — the goal is to improve the iterative shifter
- All other CPU functionality must remain unchanged