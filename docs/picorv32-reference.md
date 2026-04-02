# picorv32 Quick Reference

## What It Is

A size-optimized RISC-V RV32IMC CPU core written in a single Verilog file (`picorv32.v`).
Created by Claire Xenia Wolf (YosysHQ). Public domain.

---

## Modules in picorv32.v

| Module | Lines (approx) | Description | Good Optimization Target? |
|--------|----------------|-------------|--------------------------|
| `picorv32` | ~2800 | Main CPU core, highly parameterized | Yes -- largest, most room for optimization |
| `picorv32_regs` | ~50 | Register file (32x32-bit) | Yes -- small, self-contained |
| `picorv32_pcpi_mul` | ~150 | Multi-cycle multiplier | Yes -- clear optimization goal |
| `picorv32_pcpi_fast_mul` | ~100 | Pipelined fast multiplier | Yes -- can trade area/speed |
| `picorv32_pcpi_div` | ~80 | Divider unit | Yes -- small, testable |
| `picorv32_axi` | ~200 | AXI4 bus wrapper around core | Moderate |
| `picorv32_axi_adapter` | ~150 | Native-to-AXI protocol adapter | Moderate |
| `picorv32_wb` | ~200 | Wishbone bus wrapper | Moderate |

---

## Key Parameters (picorv32 module)

```verilog
picorv32 #(
    .ENABLE_COUNTERS(1),      // Cycle/instruction counters
    .ENABLE_COUNTERS64(1),    // 64-bit counters
    .ENABLE_REGS_16_31(1),    // Registers x16-x31 (set 0 for RV32E)
    .ENABLE_REGS_DUALPORT(1), // Dual-port register file
    .ENABLE_MUL(0),           // Hardware multiply (PCPI)
    .ENABLE_FAST_MUL(0),      // Fast pipelined multiply
    .ENABLE_DIV(0),           // Hardware divide
    .ENABLE_IRQ(0),           // Interrupt support
    .ENABLE_TRACE(0),         // Instruction trace output
    .BARREL_SHIFTER(0),       // Use barrel shifter (faster, bigger)
    .TWO_CYCLE_COMPARE(0),    // Split compare into 2 cycles
    .TWO_CYCLE_ALU(0),        // Split ALU ops into 2 cycles
    .COMPRESSED_ISA(0)        // RV32C compressed instructions
) cpu (
    .clk(clk),
    .resetn(resetn),          // Active-low reset
    .trap(trap),              // Goes high on illegal instruction/timeout
    // Memory interface...
);
```

**These parameters are your optimization levers.** Toggling them changes area/performance tradeoffs.

---

## Memory Interface (Native)

```
clk          -- system clock
resetn       -- active-low reset
trap         -- CPU halted (illegal insn, etc.)

mem_valid    -- CPU requests memory access
mem_instr    -- 1 = instruction fetch, 0 = data
mem_ready    -- Memory acknowledges (active 1 cycle)
mem_addr     -- 32-bit address
mem_wdata    -- 32-bit write data
mem_wstrb    -- 4-bit byte-enable for writes (0 = read)
mem_rdata    -- 32-bit read data from memory
```

---

## Testbench Quick Start

### testbench_ez.v (Simplest -- no firmware)

Has hardcoded RISC-V instructions in the testbench. Self-contained.

```bash
iverilog -o tb_ez.vvp testbench_ez.v picorv32.v
vvp tb_ez.vvp
```

### testbench.v (Full -- needs firmware)

Requires cross-compiled firmware (`firmware/firmware.hex`). The Makefile handles this.

```bash
# Needs riscv32 toolchain at /opt/riscv32i/bin/
make test
```

---

## Optimization Ideas for Benchmark Tasks

1. **Reduce area of `picorv32_pcpi_mul`**: Replace multi-cycle multiplier with shift-add, or reduce bit-width
2. **Simplify register file**: If targeting RV32E (16 regs), optimize `picorv32_regs` for fewer ports
3. **Remove unused features**: Strip counters, IRQ, trace from main core -- measure area savings
4. **Optimize FSM encoding**: The main core uses a large case-based FSM -- one-hot vs binary encoding
5. **Pipeline tradeoffs in `picorv32_pcpi_fast_mul`**: Change pipeline depth, measure area vs timing
6. **Bus adapter optimization**: Simplify `picorv32_axi_adapter` protocol handling
7. **ALU sharing**: Merge duplicate logic paths in the main decode/execute

---

## Gotchas

- The main `picorv32` module is **very large** (~2800 lines). For benchmark tasks, prefer targeting submodules or parameter-gated sections.
- `trap` signal going high doesn't always mean an error -- it triggers on `ebreak` too.
- Memory interface is **not** pipelined -- one outstanding request at a time.
- Parameters interact: e.g., `ENABLE_MUL` and `ENABLE_FAST_MUL` are mutually exclusive.
