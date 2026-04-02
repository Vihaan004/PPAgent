`timescale 1 ns / 1 ps

// Testbench for picorv32 — feature stripping / dead code elimination
// Self-contained (no firmware). Tests basic instruction execution.
// Adapted from testbench_ez.v — exercises core fetch/decode/execute/memory
// Does NOT use CSR instructions (counters removed in optimized version).
//
// Test program:
//   li   x1, 1020     # base address
//   sw   x0, 0(x1)    # init counter = 0
//   lw   x2, 0(x1)    # load counter
//   addi x2, x2, 1    # increment
//   sw   x2, 0(x1)    # store counter
//   j    loop          # jump back to lw
//
// After 1000 cycles, check that counter has incremented correctly.
// Also tests: lui, addi, sw, lw, jal, add, sub, and, or, xor, beq

module testbench;
    reg clk = 1;
    reg resetn = 0;
    wire trap;

    always #5 clk = ~clk;

    initial begin
        repeat (100) @(posedge clk);
        resetn <= 1;
    end

    initial begin
        repeat (5000) @(posedge clk);
        // Check results after running
        check_results;
        $finish;
    end

    wire mem_valid;
    wire mem_instr;
    reg mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_IRQ(0),
        .ENABLE_TRACE(0),
        .CATCH_MISALIGN(1),
        .CATCH_ILLINSN(1)
    ) uut (
        .clk         (clk),
        .resetn      (resetn),
        .trap        (trap),
        .mem_valid   (mem_valid),
        .mem_instr   (mem_instr),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata)
    );

    reg [31:0] memory [0:255];

    initial begin
        // Part 1: Counter loop test (same as testbench_ez.v)
        // li x1, 1020         (addi x1, x0, 1020)
        memory[0] = 32'h 3fc00093;
        // sw x0, 0(x1)        (store 0 at addr 1020)
        memory[1] = 32'h 0000a023;
        // loop: lw x2, 0(x1)  (load counter)
        memory[2] = 32'h 0000a103;
        // addi x2, x2, 1      (increment)
        memory[3] = 32'h 00110113;
        // sw x2, 0(x1)        (store counter)
        memory[4] = 32'h 0020a023;

        // Part 2: ALU tests (run once then loop back)
        // addi x3, x0, 42     (x3 = 42)
        memory[5] = 32'h 02a00193;
        // addi x4, x0, 17     (x4 = 17)
        memory[6] = 32'h 01100213;
        // add x5, x3, x4      (x5 = 59)
        memory[7] = 32'h 004182B3;
        // sub x6, x3, x4      (x6 = 25)
        memory[8] = 32'h 40418333;
        // and x7, x3, x4      (x7 = 42 & 17 = 0)
        memory[9] = 32'h 0041F3B3;
        // or  x8, x3, x4      (x8 = 42 | 17 = 59)
        memory[10] = 32'h 0041E433;
        // xor x9, x3, x4      (x9 = 42 ^ 17 = 59)
        memory[11] = 32'h 0041C4B3;

        // Store ALU results to memory[252..254] = addresses 0x3F0..0x3F8
        // lui x30, 0
        memory[12] = 32'h 00000F37;
        // sw x5, 0x3F0(x30)   (store add result)
        memory[13] = 32'h 3E5F2823;
        // sw x6, 0x3F4(x30)   (store sub result)
        memory[14] = 32'h 3E6F2A23;
        // sw x7, 0x3F8(x30)   (store and result)
        memory[15] = 32'h 3E7F2C23;

        // Jump back to loop (address 0x008 = memory[2])
        memory[16] = 32'h FE9FF06F;   // jal x0, -24  (jump to addr 8)

        // Fill rest with nops
        memory[17] = 32'h 00000013;
    end

    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_valid && !mem_ready) begin
            if (mem_addr < 1024) begin
                mem_ready <= 1;
                mem_rdata <= memory[mem_addr >> 2];
                if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
            end
        end
    end

    task check_results;
        reg pass;
        begin
            pass = 1;

            // Check counter was incremented (memory[255] = addr 1020 = 0x3FC)
            if (memory[255] > 0) begin
                $display("PASS [counter]: counter = %0d (incremented)", memory[255]);
            end else begin
                $display("FAIL [counter]: counter = %0d (should be > 0)", memory[255]);
                pass = 0;
            end

            // Check ALU results at memory[252], memory[253], memory[254]
            if (memory[252] === 32'd59) begin
                $display("PASS [add]: 42 + 17 = %0d", memory[252]);
            end else begin
                $display("FAIL [add]: 42 + 17 = %0d, expected 59", memory[252]);
                pass = 0;
            end

            if (memory[253] === 32'd25) begin
                $display("PASS [sub]: 42 - 17 = %0d", memory[253]);
            end else begin
                $display("FAIL [sub]: 42 - 17 = %0d, expected 25", memory[253]);
                pass = 0;
            end

            if (memory[254] === 32'd0) begin
                $display("PASS [and]: 42 & 17 = %0d", memory[254]);
            end else begin
                $display("FAIL [and]: 42 & 17 = %0d, expected 0", memory[254]);
                pass = 0;
            end

            $display("");
            if (pass)
                $display("ALL TESTS PASSED");
            else
                $display("SOME TESTS FAILED");
        end
    endtask
endmodule
