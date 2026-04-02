# Yosys Synthesis Quick Reference

## What It Does

Open-source RTL synthesis tool. Reads Verilog, optimizes logic, maps to cells, and reports stats.
In this project: **PPA metrics extractor** -- cell count (area), FF count (power proxy), critical path depth (timing proxy).

---

## One-Liner for PPA Metrics

```bash
yosys -p "read_verilog design.v; synth -top <module_name>; stat"
```

This is the command you'll use 90% of the time.

---

## Breaking Down the Synthesis Flow

```bash
yosys -p "
  read_verilog design.v;       # Parse Verilog
  synth -top picorv32;         # Run full synthesis (optimize + map to generic cells)
  stat;                        # Print area/cell statistics
"
```

### What `synth` Does Internally

`synth -top <module>` is a macro that runs: `hierarchy` -> `proc` -> `opt` -> `memory` -> `techmap` -> `abc` -> `opt_clean`. You rarely need to run these individually.

---

## Reading the `stat` Output

```
=== picorv32 ===

   Number of wires:           4637
   Number of wire bits:       9785
   Number of cells:           8127      <-- AREA PROXY
   
     $_AND_          1842              
     $_NOT_           567              
     $_OR_            923              
     $_DFF_PP_        516              <-- FF COUNT (power proxy)
     $_MUX_          1205              
     ...
```

### Key Metrics for Your Benchmark

| Metric | Stat Field | PPA Dimension |
|--------|-----------|---------------|
| **Cell count** | `Number of cells` | Area |
| **FF count** | `$_DFF_*` cells | Power (fewer FFs = less switching) |
| **Wire count** | `Number of wire bits` | Interconnect complexity |

---

## Flags You'll Use

| Flag | Purpose | Example |
|------|---------|---------|
| `-p "<commands>"` | Run Yosys commands inline | `yosys -p "read_verilog f.v; synth; stat"` |
| `-q` | Quiet mode (suppress banner/info) | `yosys -qp "..."` |
| `-l <file>` | Log output to file | `yosys -l synth.log -p "..."` |
| `-v <N>` | Verbosity level (0-9) | `yosys -v2 -p "..."` |

---

## picorv32-Specific Commands

```bash
# Synthesize the main CPU core
yosys -p "read_verilog picorv32.v; synth -top picorv32; stat"

# Synthesize a specific submodule (e.g., the multiplier)
yosys -p "read_verilog picorv32.v; synth -top picorv32_pcpi_mul; stat"

# Synthesize and also run ABC optimization (already part of synth, but explicit)
yosys -p "read_verilog picorv32.v; synth -top picorv32; abc -g AND,OR,NOT; stat"
```

### Modules You Can Synthesize

| Module | Description | Params |
|--------|-------------|--------|
| `picorv32` | Main CPU core | Many (see picorv32.v) |
| `picorv32_regs` | Register file | - |
| `picorv32_pcpi_mul` | Standard multiplier | - |
| `picorv32_pcpi_fast_mul` | Fast/pipelined multiplier | - |
| `picorv32_pcpi_div` | Divider | - |
| `picorv32_axi` | AXI bus wrapper | - |
| `picorv32_wb` | Wishbone bus wrapper | - |

---

## Extracting Metrics Programmatically

```bash
# Pipe stat output to a file, then parse
yosys -qp "read_verilog design.v; synth -top picorv32; stat" 2>&1 | tee synth.log

# Extract cell count
grep "Number of cells:" synth.log | awk '{print $NF}'

# Extract all DFF counts
grep '$_DFF_' synth.log | awk '{sum += $NF} END {print sum}'
```

### JSON Output (Yosys 0.9+)

```bash
yosys -p "read_verilog design.v; synth -top picorv32; stat -json" 2>&1 | \
  python3 -c "import sys,json; [print(l) for l in sys.stdin if l.strip().startswith('{')]"
```

> Note: Yosys 0.9 in the Docker image has limited JSON support. Parsing text output is more reliable.

---

## Yosys Optimization Passes (Baseline Comparisons)

For Subtask 4, you need a "Yosys-only" baseline. Run extra optimization:

```bash
yosys -p "
  read_verilog design.v;
  synth -top picorv32;
  opt;              # General optimization
  opt_clean;        # Remove unused cells/wires
  abc -g AND,OR,NOT;  # Re-run ABC logic minimization
  stat;
"
```

---

## Common Pitfalls

1. **Wrong `-top`**: If you don't specify `-top`, Yosys picks one arbitrarily -- always specify it
2. **Params via defines**: picorv32 uses Verilog parameters. To change them:
   ```bash
   yosys -p "read_verilog -D ENABLE_MUL=1 picorv32.v; synth -top picorv32; stat"
   ```
3. **stderr vs stdout**: Yosys prints most output to stderr. Use `2>&1` when capturing
4. **Cell count varies**: Different synthesis settings produce different counts -- always compare using identical Yosys commands
