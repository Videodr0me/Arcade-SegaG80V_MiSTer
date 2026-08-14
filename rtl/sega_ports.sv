`default_nettype none

// ---------------------------------------------------------------------------
// Input matrix: U1, U2, U5, and U9, four 74LS253 dual 4-to-1 muxes on the CPU
// board. Port address bits [1:0] drive the shared select lines, so each read of
// $F8..$FB gathers one bit from each half of each mux:
//
//         offset 0    offset 1   offset 2   offset 3
//   D7    COINA         n/c        n/c        n/c
//   D6    COINB        P1.13      P1.14       n/c     (P1.13 = DRAW)
//   D5    SERVICE      P1.15      P1.16      P1.17
//   D4    P1.18        P1.19      P1.20      P1.21
//   D3    SW1.8        SW1.7      SW1.6      SW1.5
//   D2    SW1.4        SW1.3      SW1.2      SW1.1
//   D1    SW2.8        SW2.7      SW2.6      SW2.5
//   D0    SW2.4        SW2.3      SW2.2      SW2.1
//
// The four source bytes are wired as the schematic shows them, so the matrix
// above falls out of the transposition rather than being built by hand.
// ---------------------------------------------------------------------------
module sega_mangled_ports (
	input  wire [1:0] sel,      // port address bits [1:0]
	input  wire [7:0] d7d6,
	input  wire [7:0] d5d4,
	input  wire [7:0] d3d2,
	input  wire [7:0] d1d0,
	output wire [7:0] dout
);
	wire [3:0] d7 = d7d6[3:0];
	wire [3:0] d6 = d7d6[7:4];
	wire [3:0] d5 = d5d4[3:0];
	wire [3:0] d4 = d5d4[7:4];
	wire [3:0] d3 = d3d2[3:0];
	wire [3:0] d2 = d3d2[7:4];
	wire [3:0] d1 = d1d0[3:0];
	wire [3:0] d0 = d1d0[7:4];

	assign dout = {
		d7[sel],
		d6[sel],
		d5[sel],
		d4[sel],
		d3[sel],
		d2[sel],
		d1[sel],
		d0[sel]
	};
endmodule


// ---------------------------------------------------------------------------
// Spinner (Zektor, Tac/Scan, Star Trek).
//
// Not a quadrature reading: the port returns a count that always *increases*
// however the knob is turned, with the direction in bit 0. The self-test relies
// on that. Bit 0 of the select latch swaps the port over to the raw FC inputs.
// ---------------------------------------------------------------------------
module sega_spinner (
	input  wire        clk,
	input  wire        reset,

	input  wire  [8:0] magnitude,
	input  wire        direction,
	input  wire        step_stb,

	input  wire  [7:0] fc_in,          // raw FC inputs
	input  wire        sel_raw,        // spinner_select[0]

	output wire  [7:0] dout
);
	logic [6:0] count;
	logic       direction_q;

	always_ff @(posedge clk) begin
		if (reset) begin
			count       <= 7'd0;
			direction_q <= 1'b0;
		end else if (step_stb && (magnitude != 9'd0)) begin
			count       <= count + magnitude[6:0];
			direction_q <= direction;
		end
	end

	assign dout = sel_raw ? fc_in : ~{count, direction_q};
endmodule


// ---------------------------------------------------------------------------
// Eliminator 4-player input demux.
//
// Bit 3 of the select latch enables an LS240; bits [2:0] pick the source, but
// only 6 (players 3 and 4) and 7 (the four coin inputs) are connected. The
// LS240 has inverting outputs, hence the final XOR.
// ---------------------------------------------------------------------------
module sega_elim4_ports (
	input  wire [7:0] sel,
	input  wire [7:0] fc_in,     // players 3 and 4
	input  wire [7:0] coins_in,  // the four coin inputs
	output wire [7:0] dout
);
	logic [7:0] mux;
	always_comb begin
		mux = 8'h00;
		if (sel[3]) begin
			case (sel[2:0])
				3'd6: mux = fc_in;
				3'd7: mux = coins_in;
				default: mux = 8'h00;
			endcase
		end
	end
	assign dout = mux ^ 8'hFF;
endmodule


// ---------------------------------------------------------------------------
// CPU-visible multiplier at $BD/$BE.
//
// This is the second 25LS14 on the X-Y Control board (U43, with the LS95 shift
// registers U44/U45; see XY_Control_800-0163_sheet6of6.png), not a CPU-board
// part; it lives here because it is reached purely through the I/O map.
//
// Writing $BD loads operand 0, writing $BE loads operand 1 and starts the
// multiply. Reading $BE returns the low byte first, then the high byte: each
// read shifts the result down by 8.
// ---------------------------------------------------------------------------
module sega_multiplier (
	input  wire        clk,
	input  wire        reset,

	input  wire        wr,        // write strobe
	input  wire        wr_sel,    // 0 = $BD (operand 0), 1 = $BE (operand 1)
	input  wire  [7:0] din,

	input  wire        rd,        // read strobe, $BE
	output wire  [7:0] dout
);
	logic [7:0] op0;
	logic [15:0] result;

	assign dout = result[7:0];

	always_ff @(posedge clk) begin
		if (reset) begin
			op0    <= 8'd0;
			result <= 16'd0;
		end else if (wr) begin
			if (!wr_sel) begin
				op0 <= din;
			end else begin
				result <= {8'd0, op0} * {8'd0, din};
			end
		end else if (rd) begin
			result <= {8'd0, result[15:8]};
		end
	end
endmodule

`default_nettype wire
