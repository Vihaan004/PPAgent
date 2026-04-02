module picorv32_pcpi_div (
	input clk, resetn,

	input             pcpi_valid,
	input      [31:0] pcpi_insn,
	input      [31:0] pcpi_rs1,
	input      [31:0] pcpi_rs2,
	output reg        pcpi_wr,
	output reg [31:0] pcpi_rd,
	output reg        pcpi_wait,
	output reg        pcpi_ready
);
	reg instr_div, instr_divu, instr_rem, instr_remu;
	wire instr_any_div_rem = |{instr_div, instr_divu, instr_rem, instr_remu};

	reg pcpi_wait_q;
	wire start = pcpi_wait && !pcpi_wait_q;

	always @(posedge clk) begin
		instr_div <= 0;
		instr_divu <= 0;
		instr_rem <= 0;
		instr_remu <= 0;

		if (resetn && pcpi_valid && !pcpi_ready && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001) begin
			case (pcpi_insn[14:12])
				3'b100: instr_div <= 1;
				3'b101: instr_divu <= 1;
				3'b110: instr_rem <= 1;
				3'b111: instr_remu <= 1;
			endcase
		end

		pcpi_wait <= instr_any_div_rem && resetn;
		pcpi_wait_q <= pcpi_wait && resetn;
	end

	reg [31:0] dividend;
	reg [31:0] divisor_abs; // store absolute divisor (32 bits) instead of 63-bit shifted value
	reg [31:0] quotient;
	reg running;
	reg outsign;
	// small counter representing remaining bits to process (0..32)
	reg [5:0] bits_left;

	// step size for FORMAL altops (combinational constant)
	`ifdef RISCV_FORMAL_ALTOPS
	wire [5:0] step = 6'd5;
	`else
	wire [5:0] step = 6'd1;
	`endif
	// combinational index and shifted divisor (no wide shift register stored)
	wire [5:0] idx = bits_left - 1;
	wire [62:0] shifted_div = { {31{1'b0}}, divisor_abs } << idx;

	always @(posedge clk) begin
		pcpi_ready <= 0;
		pcpi_wr <= 0;
		pcpi_rd <= 'bx;

		if (!resetn) begin
			running <= 0;
		end else
		if (start) begin
			running <= 1;
			dividend <= (instr_div || instr_rem) && pcpi_rs1[31] ? -pcpi_rs1 : pcpi_rs1;
			divisor_abs <= ((instr_div || instr_rem) && pcpi_rs2[31] ? -pcpi_rs2 : pcpi_rs2);
			outsign <= (instr_div && (pcpi_rs1[31] != pcpi_rs2[31]) && |pcpi_rs2) || (instr_rem && pcpi_rs1[31]);
			quotient <= 0;
			bits_left <= 6'd32;
		end else
		if (!bits_left && running) begin
			running <= 0;
			pcpi_ready <= 1;
			pcpi_wr <= 1;
`ifdef RISCV_FORMAL_ALTOPS
			case (1)
				instr_div:  pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h7f8529ec;
				instr_divu: pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h10e8fd70;
				instr_rem:  pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h8da68fa5;
				instr_remu: pcpi_rd <= (pcpi_rs1 - pcpi_rs2) ^ 32'h3138d0e1;
			endcase
`else
			if (instr_div || instr_divu)
				pcpi_rd <= outsign ? -quotient : quotient;
			else
				pcpi_rd <= outsign ? -dividend : dividend;
`endif
		end else if (running) begin
			// perform one (or several, under FORMAL altops) division steps using a small counter
			// compute current bit index as bits_left-1 when bits_left != 0
			// clamp next_bits to zero when stepping past zero
			if (bits_left > step)
				bits_left <= bits_left - step;
			else
				bits_left <= 0;

			// compare combinational shifted divisor and update dividend/quotient
			if (shifted_div <= {31'b0, dividend}) begin
				dividend <= dividend - shifted_div[31:0];
				quotient <= quotient | (32'h1 << idx[4:0]);
			end
		end
	end
endmodule
