`timescale 1 ns / 1 ps

// Testbench for picorv32_pcpi_div — drives PCPI interface directly
// Tests: div, divu, rem, remu with edge cases (div-by-zero, MIN_INT/-1, etc.)

module testbench;
    reg clk = 1;
    reg resetn = 0;

    always #5 clk = ~clk;

    reg             pcpi_valid;
    reg      [31:0] pcpi_insn;
    reg      [31:0] pcpi_rs1;
    reg      [31:0] pcpi_rs2;
    wire            pcpi_wr;
    wire     [31:0] pcpi_rd;
    wire            pcpi_wait;
    wire            pcpi_ready;

    picorv32_pcpi_div uut (
        .clk       (clk),
        .resetn    (resetn),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn (pcpi_insn),
        .pcpi_rs1  (pcpi_rs1),
        .pcpi_rs2  (pcpi_rs2),
        .pcpi_wr   (pcpi_wr),
        .pcpi_rd   (pcpi_rd),
        .pcpi_wait (pcpi_wait),
        .pcpi_ready(pcpi_ready)
    );

    // RISC-V M-extension division instructions (R-type, opcode=0110011, funct7=0000001)
    // funct3: 100=div, 101=divu, 110=rem, 111=remu
    localparam [31:0] INSN_DIV  = 32'b0000001_00000_00000_100_00000_0110011;
    localparam [31:0] INSN_DIVU = 32'b0000001_00000_00000_101_00000_0110011;
    localparam [31:0] INSN_REM  = 32'b0000001_00000_00000_110_00000_0110011;
    localparam [31:0] INSN_REMU = 32'b0000001_00000_00000_111_00000_0110011;

    integer test_num;
    integer pass_count;
    integer fail_count;
    integer timeout_counter;

    task run_div_test;
        input [31:0] insn;
        input [31:0] rs1;
        input [31:0] rs2;
        input [31:0] expected;
        input [255:0] test_name;
        begin
            test_num = test_num + 1;
            @(posedge clk);
            pcpi_valid <= 1;
            pcpi_insn  <= insn;
            pcpi_rs1   <= rs1;
            pcpi_rs2   <= rs2;

            // Wait for ready (with timeout — division takes ~35 cycles)
            timeout_counter = 0;
            while (!pcpi_ready && timeout_counter < 200) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (timeout_counter >= 200) begin
                $display("FAIL test %0d [%0s]: TIMEOUT", test_num, test_name);
                fail_count = fail_count + 1;
            end else if (pcpi_rd !== expected) begin
                $display("FAIL test %0d [%0s]: got 0x%08x, expected 0x%08x", test_num, test_name, pcpi_rd, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS test %0d [%0s]: 0x%08x", test_num, test_name, pcpi_rd);
                pass_count = pass_count + 1;
            end

            pcpi_valid <= 0;
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        pcpi_valid = 0;

        // Reset
        repeat (10) @(posedge clk);
        resetn <= 1;
        repeat (5) @(posedge clk);

        // ===== DIV (signed division) =====
        // RISC-V spec: div rd, rs1, rs2 => rd = signed(rs1) / signed(rs2)
        run_div_test(INSN_DIV, 32'd20,  32'd3,   32'd6,          "div 20/3");
        run_div_test(INSN_DIV, 32'd20,  32'd4,   32'd5,          "div 20/4");
        run_div_test(INSN_DIV, -32'd20, 32'd3,   -32'd6,         "div -20/3");
        run_div_test(INSN_DIV, 32'd20,  -32'd3,  -32'd6,         "div 20/-3");
        run_div_test(INSN_DIV, -32'd20, -32'd3,  32'd6,          "div -20/-3");
        // Division by zero: RISC-V spec says result = -1 (all ones)
        run_div_test(INSN_DIV, 32'd10,  32'd0,   32'hFFFFFFFF,   "div 10/0");
        // Overflow: MIN_INT / -1 = MIN_INT (RISC-V spec)
        run_div_test(INSN_DIV, 32'h80000000, 32'hFFFFFFFF, 32'h80000000, "div MIN/-1");
        run_div_test(INSN_DIV, 32'd1,   32'd1,   32'd1,          "div 1/1");
        run_div_test(INSN_DIV, 32'd0,   32'd5,   32'd0,          "div 0/5");

        // ===== DIVU (unsigned division) =====
        run_div_test(INSN_DIVU, 32'd20,  32'd3,   32'd6,         "divu 20/3");
        run_div_test(INSN_DIVU, 32'hFFFFFFFF, 32'd2, 32'h7FFFFFFF, "divu MAX_U/2");
        run_div_test(INSN_DIVU, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "divu MAX_U/1");
        // Div by zero: result = MAX_U (all ones)
        run_div_test(INSN_DIVU, 32'd10,  32'd0,  32'hFFFFFFFF,   "divu 10/0");
        run_div_test(INSN_DIVU, 32'd0,   32'd5,  32'd0,          "divu 0/5");

        // ===== REM (signed remainder) =====
        // RISC-V spec: rem rd, rs1, rs2 => rd = signed(rs1) % signed(rs2), sign follows dividend
        run_div_test(INSN_REM, 32'd20,  32'd3,   32'd2,          "rem 20%3");
        run_div_test(INSN_REM, -32'd20, 32'd3,   -32'd2,         "rem -20%3");
        run_div_test(INSN_REM, 32'd20,  -32'd3,  32'd2,          "rem 20%-3");
        run_div_test(INSN_REM, -32'd20, -32'd3,  -32'd2,         "rem -20%-3");
        // Rem by zero: result = dividend
        run_div_test(INSN_REM, 32'd10,  32'd0,   32'd10,         "rem 10%0");
        // Overflow: MIN_INT % -1 = 0
        run_div_test(INSN_REM, 32'h80000000, 32'hFFFFFFFF, 32'd0, "rem MIN%-1");

        // ===== REMU (unsigned remainder) =====
        run_div_test(INSN_REMU, 32'd20,  32'd3,   32'd2,         "remu 20%3");
        run_div_test(INSN_REMU, 32'hFFFFFFFF, 32'd7, 32'd3,      "remu MAX_U%7");
        // Rem by zero: result = dividend
        run_div_test(INSN_REMU, 32'd10,  32'd0,   32'd10,        "remu 10%0");
        run_div_test(INSN_REMU, 32'd0,   32'd5,   32'd0,         "remu 0%5");

        // Summary
        $display("");
        $display("========================================");
        $display("  Results: %0d passed, %0d failed out of %0d tests", pass_count, fail_count, test_num);
        $display("========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Global timeout
    initial begin
        #1000000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end
endmodule
