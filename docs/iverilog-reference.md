# Icarus Verilog (iverilog) Quick Reference

## What It Does

Compiles Verilog source into a simulation executable, then `vvp` runs it.
In this project: **correctness oracle** -- does optimized RTL still behave identically to the original?

---

## Two-Step Flow

```bash
# Step 1: Compile
iverilog -o output.vvp design.v testbench.v

# Step 2: Simulate
vvp output.vvp
```

That's it. If it prints no errors and your testbench passes, the design is functionally correct.

---

## Flags You'll Actually Use

| Flag | Purpose | Example |
|------|---------|---------|
| `-o <file>` | Name the compiled output | `iverilog -o sim.vvp top.v tb.v` |
| `-D<MACRO>` | Define a preprocessor macro | `-DCOMPRESSED_ISA` |
| `-I <dir>` | Add include search path | `-I ./rtl/` |
| `-g2012` | Enable SystemVerilog features | `-g2012 top.sv tb.sv` |
| `-Wall` | Enable all warnings | Useful for catching issues early |

---

## picorv32-Specific Commands

```bash
# Compile the main testbench (from picorv32/ directory)
iverilog -o testbench.vvp testbench.v picorv32.v

# Compile the simple/easy testbench (no firmware needed)
iverilog -o testbench_ez.vvp testbench_ez.v picorv32.v

# Compile with compressed ISA support
iverilog -o testbench.vvp -DCOMPRESSED_ISA testbench.v picorv32.v

# Run simulation
vvp testbench.vvp
```

### Testbenches in picorv32

| File | What It Tests | Needs Firmware? |
|------|--------------|-----------------|
| `testbench.v` | Full CPU with AXI memory interface | Yes (`firmware/firmware.hex`) |
| `testbench_ez.v` | Basic CPU with hardcoded instructions | **No** -- self-contained |
| `testbench_wb.v` | Wishbone bus variant | Yes |

**For your benchmark tasks, `testbench_ez.v` is the easiest starting point** -- no cross-compilation needed.

---

## Interpreting Output

- **PASS**: Simulation completes, testbench prints expected output, no `ERROR`/`FAIL` lines
- **FAIL**: Look for `$display` messages with `ERROR`, `FAIL`, or `TIMEOUT`
- **Compile error**: Syntax error in Verilog -- the optimized RTL is broken
- **TIMEOUT**: Simulation hit the cycle limit (`repeat (1000000)`) -- likely a hang/deadlock

### Checking Pass/Fail Programmatically

```bash
# Run and capture exit code + output
vvp sim.vvp 2>&1 | tee sim.log
# Check for errors
if grep -qiE "error|fail|timeout" sim.log; then
    echo "FAILED"
else
    echo "PASSED"
fi
```

---

## Writing a Minimal Testbench for Your Tasks

```verilog
`timescale 1 ns / 1 ps

module tb;
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz clock

    reg resetn = 0;
    wire trap;

    // Instantiate the module under test
    picorv32 uut (
        .clk(clk),
        .resetn(resetn),
        .trap(trap)
        // ... connect other ports
    );

    initial begin
        // Hold reset for a bit
        repeat (10) @(posedge clk);
        resetn <= 1;

        // Run for N cycles
        repeat (500) @(posedge clk);

        // Check conditions
        if (/* some condition */)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end
endmodule
```

---

## Common Pitfalls

1. **Missing files**: `iverilog` needs ALL Verilog files that define modules used in the design
2. **Module not found**: If you extract a submodule, make sure to include it AND any modules it instantiates
3. **Timescale**: Always include `` `timescale 1 ns / 1 ps `` at the top of testbenches
4. **No `$finish`**: Simulation will run forever without it -- always have a timeout
