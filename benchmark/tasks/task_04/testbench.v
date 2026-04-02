`timescale 1 ns / 1 ps

// Testbench for picorv32 — shift performance optimization
// Self-contained (no firmware). Tests slli, srli, srai with various shift amounts.
// Stores results to memory, checks expected values.
//
// Test program:
//   lui  x1, 0xFF00F        # x1 = 0xFF00F000
//   ori  x1, x1, 0x0F0      # x1 = 0xFF00F0F0
//   slli x2, x1, 1           # x2 = 0xFE01E1E0
//   slli x3, x1, 4           # x3 = 0xF00F0F00
//   slli x4, x1, 16          # x4 = 0xF0F00000
//   slli x5, x1, 31          # x5 = 0x00000000
//   srli x6, x1, 4           # x6 = 0x0FF00F0F
//   srli x7, x1, 16          # x7 = 0x0000FF00
//   srai x8, x1, 4           # x8 = 0xFFF00F0F (arithmetic, sign-extended)
//   srai x9, x1, 16          # x9 = 0xFFFFFF00 (arithmetic, sign-extended)
//   srli x10, x1, 31         # x10 = 0x00000001
//   slli x11, x1, 8          # x11 = 0x00F0F000  (test mid-range)
//   Store results to memory starting at address 0x200
//   Write 0x0A0A0A0A to 0x3FC as pass sentinel

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
        repeat (10000) @(posedge clk);
        $display("TIMEOUT");
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
        .BARREL_SHIFTER(0),
        .TWO_STAGE_SHIFT(1),
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_IRQ(0),
        .ENABLE_TRACE(0)
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
        // lui x1, 0xFF00F        => x1 = 0xFF00F000
        memory[0] = 32'hFF00F0B7;
        // ori x1, x1, 0x0F0      => x1 = 0xFF00F0F0
        memory[1] = 32'h0F00E093;
        // slli x2, x1, 1         => x2 = 0xFE01E1E0
        memory[2] = 32'h00109113;
        // slli x3, x1, 4         => x3 = 0xF00F0F00
        memory[3] = 32'h00409193;
        // slli x4, x1, 16        => x4 = 0xF0F00000
        memory[4] = 32'h01009213;
        // slli x5, x1, 31        => x5 = 0x00000000
        memory[5] = 32'h01F09293;
        // srli x6, x1, 4         => x6 = 0x0FF00F0F
        memory[6] = 32'h0040D313;
        // srli x7, x1, 16        => x7 = 0x0000FF00
        memory[7] = 32'h0100D393;
        // srai x8, x1, 4         => x8 = 0xFFF00F0F
        memory[8] = 32'h4040D413;
        // srai x9, x1, 16        => x9 = 0xFFFFFF00
        memory[9] = 32'h4100D493;
        // srli x10, x1, 31       => x10 = 0x00000001
        memory[10] = 32'h01F0D513;
        // slli x11, x1, 8        => x11 = 0x00F0F000
        memory[11] = 32'h00809593;

        // Now store results to memory at 0x200 (word index 128)
        // sw x2, 0x200(x0)   — but immediate is 12-bit, so use x0 base
        // addi x31, x0, 0x200  — but 0x200 = 512, fits in 12-bit signed
        // Actually: use lui to load base address
        // lui x30, 0          => x30 = 0
        memory[12] = 32'h00000F37;
        // addi x30, x30, 0x200  => x30 = 0x200 (store base)
        // But 0x200 = 512, fits in signed 12-bit
        memory[13] = 32'h200F0F13;
        // sw x2, 0(x30)
        memory[14] = 32'h002F2023;
        // sw x3, 4(x30)
        memory[15] = 32'h003F2223;
        // sw x4, 8(x30)
        memory[16] = 32'h004F2423;
        // sw x5, 12(x30)
        memory[17] = 32'h005F2623;
        // sw x6, 16(x30)
        memory[18] = 32'h006F2823;
        // sw x7, 20(x30)
        memory[19] = 32'h007F2A23;
        // sw x8, 24(x30)
        memory[20] = 32'h008F2C23;
        // sw x9, 28(x30)
        memory[21] = 32'h009F2E23;
        // sw x10, 32(x30)  S-type: imm=32=0b0000001_00000
        memory[22] = 32'b0000001_01010_11110_010_00000_0100011;
        // sw x11, 36(x30)  S-type: imm=36=0b0000001_00100
        memory[23] = 32'b0000001_01011_11110_010_00100_0100011;

        // ebreak (causes trap to end simulation)
        memory[24] = 32'h00100073;
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

    // Check results when trap fires
    reg done;
    initial done = 0;

    integer fail_total;
    always @(posedge clk) begin
        if (resetn && trap && !done) begin
            done <= 1;
            fail_total = 0;
            // Check stored shift results at memory[128..137] (address 0x200+)
            check_result(128, 32'hFE01E1E0, "slli x1,1");
            check_result(129, 32'hF00F0F00, "slli x1,4");
            check_result(130, 32'hF0F00000, "slli x1,16");
            check_result(131, 32'h00000000, "slli x1,31");
            check_result(132, 32'h0FF00F0F, "srli x1,4");
            check_result(133, 32'h0000FF00, "srli x1,16");
            check_result(134, 32'hFFF00F0F, "srai x1,4");
            check_result(135, 32'hFFFFFF00, "srai x1,16");
            check_result(136, 32'h00000001, "srli x1,31");
            check_result(137, 32'h00F0F000, "slli x1,8");

            $display("");
            if (fail_total == 0)
                $display("ALL TESTS PASSED");
            else
                $display("SOME TESTS FAILED (%0d failures)", fail_total);

            $finish;
        end
    end

    task check_result;
        input integer idx;
        input [31:0] expected;
        input [255:0] name;
        begin
            if (memory[idx] === expected)
                $display("PASS [%0s]: 0x%08x", name, memory[idx]);
            else begin
                $display("FAIL [%0s]: got 0x%08x, expected 0x%08x", name, memory[idx], expected);
                fail_total = fail_total + 1;
            end
        end
    endtask
endmodule
