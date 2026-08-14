//============================================================================
//  Sega G-80 X-Y subsystem: vector generator + its memories
//
//  Wraps sega_xy with its vector RAM and sin/cos PROM:
//
//    * 4K x 8 vector RAM at U24-U31 on X-Y Control drawing 800-0163 sheet 5.
//      Dual-port storage preserves the CPU's fixed two-wait-state contract.
//
//    * 1K x 8 sin/cos PROM s-c.xyt-u39, loaded from the MRA ROM stream.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_xy_top #(
	parameter int PHASE_CLKS  = 16,
	parameter int BUDGET_CLKS = 64452
) (
	input  wire        clk,
	input  wire        ce,           // VCL clock enable (2.578 MHz)
	input  wire        reset,

	input  wire        frame_start,  // EDGINT, 40 Hz

	// CPU side of the vector RAM ($E000-$EFFF). The address arrives already
	// descrambled by sega_security.
	input  wire [11:0] cpu_addr,
	input  wire  [7:0] cpu_din,
	input  wire        cpu_wr,
	output wire  [7:0] cpu_dout,

	// sin/cos PROM load from the MRA ROM stream
	input  wire        rom_wr,
	input  wire  [9:0] rom_addr,
	input  wire  [7:0] rom_data,

	// Beam output, one sample per ce tick while stepping
	output wire  [9:0] out_x,
	output wire  [9:0] out_y,
	output wire  [5:0] out_colour,
	output wire        out_beam,
	output wire        out_valid,

	output wire        segment_start,
	output wire [11:0] segment_start_x,
	output wire [11:0] segment_start_y,
	output wire  [8:0] segment_duration,
	output wire  [7:0] segment_delta_x,
	output wire  [7:0] segment_delta_y,
	output wire        segment_x_negative,
	output wire        segment_y_negative,
	output wire  [5:0] segment_colour,
	output wire        segment_beam,
	output wire        segment_dot,

	output wire        drawing,      // DRAW, polled by the CPU at $F8 bit 5
	output wire        frame_done
);

	// ------------------------------------------------------------------
	// Vector RAM, true dual port, 4K x 8
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] vram [0:4095];

	wire [11:0] gen_addr;
	logic [7:0] gen_q;
	logic [7:0] cpu_q;

	// CPU port
	always_ff @(posedge clk) begin
		if (cpu_wr) vram[cpu_addr] <= cpu_din;
		cpu_q <= vram[cpu_addr];
	end
	assign cpu_dout = cpu_q;

	// The generator receives data one VCL after each read request.
	always_ff @(posedge clk) begin
		if (ce) gen_q <= vram[gen_addr];
	end

	// ------------------------------------------------------------------
	// sin/cos PROM, 1K x 8. A0 is grounded on the board, so only the even
	// entries are ever addressed; the odd half is loaded but unused.
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] sinrom [0:1023];

	wire [9:0]  sin_a;
	logic [7:0] sin_q;

	always_ff @(posedge clk) begin
		if (rom_wr) sinrom[rom_addr] <= rom_data;
		if (ce)     sin_q <= sinrom[sin_a];
	end

	// ------------------------------------------------------------------

	sega_xy #(
		.PHASE_CLKS  (PHASE_CLKS),
		.BUDGET_CLKS (BUDGET_CLKS)
	) gen (
		.clk         (clk),
		.ce          (ce),
		.reset       (reset),
		.frame_start (frame_start),

		.vram_addr   (gen_addr),
		.vram_data   (gen_q),
		.sin_addr    (sin_a),
		.sin_data    (sin_q),

		.out_x       (out_x),
		.out_y       (out_y),
		.out_colour  (out_colour),
		.out_beam    (out_beam),
		.out_valid   (out_valid),

		.segment_start          (segment_start),
		.segment_start_x        (segment_start_x),
		.segment_start_y        (segment_start_y),
		.segment_duration       (segment_duration),
		.segment_delta_x        (segment_delta_x),
		.segment_delta_y        (segment_delta_y),
		.segment_x_negative     (segment_x_negative),
		.segment_y_negative     (segment_y_negative),
		.segment_colour         (segment_colour),
		.segment_beam           (segment_beam),
		.segment_dot            (segment_dot),

		.drawing     (drawing),
		.frame_done  (frame_done)
	);

endmodule

`default_nettype wire
