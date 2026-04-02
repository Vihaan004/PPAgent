# Improvement: Testbench Coverage Strengthening

## Problem
Generated testbenches use finite hardcoded vectors. Risk of false-positive correctness on untested inputs.

## Tasks 01-03 (PCPI modules)
- Currently: ~24 vectors each
- Improvement: Add more edge-case vectors (random-ish values, boundary conditions)
- Ideal: Formal equivalence checking via `mulcmp.v`-style `$anyconst` + assertions (requires sby/smtbmc tooling not in Docker)

## Tasks 04-05 (full core)
- Currently: Short hardcoded instruction sequences testing narrow functionality
- Improvement: Add more instruction sequences covering memory ops, branching, edge cases
- Ideal: Run compiled firmware test suites (requires riscv-gcc cross-compilation pipeline)

## Conclusion
Current testbenches are sufficient to reject clearly broken optimizations (the LLM agent use case). Document this limitation in final deliverable. Revisit if time permits.
