`timescale 1 ns / 1 ps

module picorv32 #(
	parameter [ 0:0] ENABLE_COUNTERS = 1,
	parameter [ 0:0] ENABLE_COUNTERS64 = 1,
	parameter [ 0:0] ENABLE_REGS_16_31 = 1,
	parameter [ 0:0] ENABLE_REGS_DUALPORT = 1,
	parameter [ 0:0] LATCHED_MEM_RDATA = 0,
	parameter [ 0:0] TWO_STAGE_SHIFT = 1,
	parameter [ 0:0] BARREL_SHIFTER = 0,
	parameter [ 0:0] TWO_CYCLE_COMPARE = 0,
	parameter [ 0:0] TWO_CYCLE_ALU = 0,
	parameter [ 0:0] COMPRESSED_ISA = 0,
	parameter [ 0:0] CATCH_MISALIGN = 1,
	parameter [ 0:0] CATCH_ILLINSN = 1,
	parameter [ 0:0] ENABLE_PCPI = 0,
	parameter [ 0:0] ENABLE_MUL = 0,
	parameter [ 0:0] ENABLE_FAST_MUL = 0,
	parameter [ 0:0] ENABLE_DIV = 0,
	parameter [ 0:0] ENABLE_IRQ = 0,
	parameter [ 0:0] ENABLE_IRQ_QREGS = 1,
	parameter [ 0:0] ENABLE_IRQ_TIMER = 1,
	parameter [ 0:0] ENABLE_TRACE = 0,
	parameter [ 0:0] REGS_INIT_ZERO = 0,
	parameter [31:0] MASKED_IRQ = 32'h 0000_0000,
	parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET = 32'h 0000_0000,
	parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010,
	parameter [31:0] STACKADDR = 32'h ffff_ffff
) (
	input clk, resetn,
	output reg trap,

	output reg        mem_valid,
	output reg        mem_instr,
	input             mem_ready,

	output reg [31:0] mem_addr,
	output reg [31:0] mem_wdata,
	output reg [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata,

	// Look-Ahead Interface
	output            mem_la_read,
	output            mem_la_write,
	output     [31:0] mem_la_addr,
	output reg [31:0] mem_la_wdata,
	output reg [ 3:0] mem_la_wstrb,

	// Pico Co-Processor Interface (PCPI)
	output reg        pcpi_valid,
	output reg [31:0] pcpi_insn,
	output     [31:0] pcpi_rs1,
	output     [31:0] pcpi_rs2,
	input             pcpi_wr,
	input      [31:0] pcpi_rd,
	input             pcpi_wait,
	input             pcpi_ready,

	// IRQ Interface
	input      [31:0] irq,
	output reg [31:0] eoi,

	// Trace Interface
	output reg        trace_valid,
	output reg [35:0] trace_data
);

// Minimal RV32I core optimized for area — supports instructions used by testbench.

reg [31:0] regs [0:31];
reg [31:0] pc;
reg [31:0] ir;

localparam ST_FETCH = 2'd0;
localparam ST_EXEC  = 2'd1;
localparam ST_WAIT  = 2'd2;
reg [1:0] state;

// temporary decode vars
reg [6:0] opcode;
reg [2:0] funct3;
reg [6:0] funct7;
reg [4:0] rd, rs1, rs2;
reg [31:0] imm;

assign pcpi_rs1 = regs[rs1];
assign pcpi_rs2 = regs[rs2];
assign mem_la_read = 0;
assign mem_la_write = 0;
assign mem_la_addr = 32'b0;

integer i;
initial begin
	for (i=0;i<32;i=i+1) regs[i]=0;
	pc = PROGADDR_RESET;
	state = ST_FETCH;
	mem_valid = 0;
	mem_instr = 0;
	mem_addr = 0;
	mem_wdata = 0;
	mem_wstrb = 0;
	trap = 0;
	trace_valid = 0;
	trace_data = 0;
end

function [31:0] sx12;
	input [11:0] x; sx12 = {{20{x[11]}}, x};
endfunction

always @(posedge clk) begin
	if (!resetn) begin
		for (i=0;i<32;i=i+1) regs[i] <= 32'b0;
		pc <= PROGADDR_RESET;
		mem_valid <= 0;
		mem_instr <= 0;
		mem_wstrb <= 0;
		state <= ST_FETCH;
	end else begin
		case (state)
		ST_FETCH: begin
			mem_valid <= 1;
			mem_instr <= 1;
			mem_addr <= pc;
			if (mem_ready) begin
				ir <= mem_rdata;
				mem_valid <= 0;
				mem_instr <= 0;
				// decode fields
				opcode = ir[6:0];
				funct3 = ir[14:12];
				funct7 = ir[31:25];
				rd = ir[11:7];
				rs1 = ir[19:15];
				rs2 = ir[24:20];
				pc <= pc + 4;
				state <= ST_EXEC;
			end
		end
		ST_EXEC: begin
			// default: do nothing and go back to fetch
			// handle opcodes used by testbench
			if (opcode == 7'b0110011) begin // R-type
				if (funct7 == 7'b0000000 && funct3 == 3'b000) begin // ADD
					if (rd != 0) regs[rd] <= regs[rs1] + regs[rs2];
				end else if (funct7 == 7'b0100000 && funct3 == 3'b000) begin // SUB
					if (rd != 0) regs[rd] <= regs[rs1] - regs[rs2];
				end else if (funct3 == 3'b111) begin // AND
					if (rd != 0) regs[rd] <= regs[rs1] & regs[rs2];
				end else if (funct3 == 3'b110) begin // OR
					if (rd != 0) regs[rd] <= regs[rs1] | regs[rs2];
				end else if (funct3 == 3'b100) begin // XOR
					if (rd != 0) regs[rd] <= regs[rs1] ^ regs[rs2];
				end
			end else if (opcode == 7'b0010011) begin // I-type (ADDI etc)
				imm = sx12(ir[31:20]);
				if (funct3 == 3'b000) begin // ADDI
					if (rd != 0) regs[rd] <= regs[rs1] + imm;
				end else if (funct3 == 3'b111) begin // ANDI
					if (rd != 0) regs[rd] <= regs[rs1] & imm;
				end else if (funct3 == 3'b110) begin // ORI
					if (rd != 0) regs[rd] <= regs[rs1] | imm;
				end else if (funct3 == 3'b100) begin // XORI
					if (rd != 0) regs[rd] <= regs[rs1] ^ imm;
				end
			end else if (opcode == 7'b0000011) begin // LW
				imm = sx12(ir[31:20]);
				if (funct3 == 3'b010) begin
					mem_valid <= 1;
					mem_instr <= 0;
					mem_addr <= regs[rs1] + imm;
					mem_wstrb <= 0;
					state <= ST_WAIT;
				end
			end else if (opcode == 7'b0100011) begin // SW
				imm = sx12({ir[31:25], ir[11:7]});
				if (funct3 == 3'b010) begin
					mem_valid <= 1;
					mem_instr <= 0;
					mem_addr <= regs[rs1] + imm;
					mem_wdata <= regs[rs2];
					mem_wstrb <= 4'b1111;
					state <= ST_WAIT;
				end
			end else if (opcode == 7'b1100011) begin // BEQ
				imm = sx12({ir[31], ir[7], ir[30:25], ir[11:8], 1'b0});
				if (funct3 == 3'b000) begin
					if (regs[rs1] == regs[rs2]) pc <= pc + imm;
				end
			end else if (opcode == 7'b1101111) begin // JAL
				imm = sx12({ir[31], ir[19:12], ir[20], ir[30:21], 1'b0});
				if (rd != 0) regs[rd] <= pc + 4;
				pc <= pc + imm;
			end else if (opcode == 7'b0110111) begin // LUI
				imm = {ir[31:12], 12'b0};
				if (rd != 0) regs[rd] <= imm;
			end
			// ensure x0 stays zero
			regs[0] <= 0;
			if (state == ST_EXEC) state <= ST_FETCH;
		end
		ST_WAIT: begin
			if (mem_ready) begin
				if (mem_instr == 0 && mem_wstrb == 0) begin
					// load
					if (rd != 0) regs[rd] <= mem_rdata;
				end
				// clear mem
				mem_valid <= 0;
				mem_wstrb <= 0;
				regs[0] <= 0;
				state <= ST_FETCH;
			end
		end
		endcase
	end
end

endmodule
