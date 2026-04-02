`timescale 1 ns / 1 ps

// Testbench for picorv32_pcpi_fast_mul — drives PCPI interface directly
// Tests: mul, mulh, mulhsu, mulhu with edge cases
// Same functional tests as task_01 but expects faster completion (2-3 cycles)

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

    picorv32_pcpi_fast_mul uut (
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

    // RISC-V M-extension instruction encodings
    localparam [31:0] INSN_MUL    = 32'b0000001_00000_00000_000_00000_0110011;
    localparam [31:0] INSN_MULH   = 32'b0000001_00000_00000_001_00000_0110011;
    localparam [31:0] INSN_MULHSU = 32'b0000001_00000_00000_010_00000_0110011;
    localparam [31:0] INSN_MULHU  = 32'b0000001_00000_00000_011_00000_0110011;

    integer test_num;
    integer pass_count;
    integer fail_count;
    integer timeout_counter;

    task run_mul_test;
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

            // Wait for ready (with timeout)
            timeout_counter = 0;
            while (!pcpi_ready && timeout_counter < 50) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end

            if (timeout_counter >= 50) begin
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

        // ===== MUL (lower 32 bits) =====
        run_mul_test(INSN_MUL, 32'd7,  32'd3,  32'd21,     "mul 7*3");
        run_mul_test(INSN_MUL, 32'd0,  32'd100, 32'd0,     "mul 0*100");
        run_mul_test(INSN_MUL, 32'd1,  32'd1,  32'd1,      "mul 1*1");
        run_mul_test(INSN_MUL, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "mul -1*1");
        run_mul_test(INSN_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1, "mul -1*-1");
        run_mul_test(INSN_MUL, 32'h80000000, 32'd2, 32'h00000000, "mul MIN*2 lo");
        run_mul_test(INSN_MUL, 32'd1000, 32'd1000, 32'd1000000,   "mul 1000*1000");
        run_mul_test(INSN_MUL, 32'hDEADBEEF, 32'd1, 32'hDEADBEEF, "mul DEADBEEF*1");

        // ===== MULH (upper 32 bits, signed*signed) =====
        run_mul_test(INSN_MULH, 32'd7,  32'd3,  32'd0,     "mulh 7*3");
        run_mul_test(INSN_MULH, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "mulh -1*1");
        run_mul_test(INSN_MULH, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0, "mulh -1*-1");
        run_mul_test(INSN_MULH, 32'h80000000, 32'd2, 32'hFFFFFFFF, "mulh MIN*2");
        run_mul_test(INSN_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF, "mulh MAX*MAX");
        run_mul_test(INSN_MULH, 32'd0, 32'h80000000, 32'd0, "mulh 0*MIN");

        // ===== MULHSU (upper 32 bits, signed*unsigned) =====
        run_mul_test(INSN_MULHSU, 32'd7,  32'd3,  32'd0,   "mulhsu 7*3");
        run_mul_test(INSN_MULHSU, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "mulhsu -1*1");
        run_mul_test(INSN_MULHSU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, "mulhsu -1*MAX_U");
        run_mul_test(INSN_MULHSU, 32'd1, 32'hFFFFFFFF, 32'd0, "mulhsu 1*MAX_U");
        run_mul_test(INSN_MULHSU, 32'h80000000, 32'd1, 32'hFFFFFFFF, "mulhsu MIN*1");

        // ===== MULHU (upper 32 bits, unsigned*unsigned) =====
        run_mul_test(INSN_MULHU, 32'd7,  32'd3,  32'd0,    "mulhu 7*3");
        run_mul_test(INSN_MULHU, 32'hFFFFFFFF, 32'd1, 32'd0, "mulhu MAX_U*1");
        run_mul_test(INSN_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE, "mulhu MAX_U*MAX_U");
        run_mul_test(INSN_MULHU, 32'h80000000, 32'd2, 32'd1, "mulhu 0x80000000*2");
        run_mul_test(INSN_MULHU, 32'd0, 32'hFFFFFFFF, 32'd0, "mulhu 0*MAX_U");

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
        #200000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end
endmodule
