//============================================================================
//  Sega G-80 discrete sound boards
//
//  Written by Videodr0me
//  Improved by Videodr0me from schematics.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_discrete #(
	parameter int CLK_HZ = 15_468_480,
	parameter int CE_HZ  = 48_000
) (
	input  wire        clk,
	input  wire        reset,
	input  wire  [2:0] game,
	input  wire        wr,
	input  wire        sel,
	input  wire  [7:0] din,
	input  wire  [7:0] ay_a,
	input  wire  [7:0] ay_b,
	input  wire  [7:0] ay_c,
	output wire signed [15:0] audio
);
	import sega_game_pkg::*;

	// Run the analog model at a fixed 48 kHz sample rate.
	localparam logic [24:0] MASTER_HZ = 25'(CLK_HZ);
	localparam logic [24:0] SAMPLE_HZ = 25'(CE_HZ);
	logic [24:0] sample_acc;
	logic sample_ce;
	wire [24:0] sample_next = sample_acc + SAMPLE_HZ;

	always_ff @(posedge clk) begin
		if (reset) begin
			sample_acc <= '0;
			sample_ce  <= 1'b0;
		end else if (sample_next >= MASTER_HZ) begin
			sample_acc <= sample_next - MASTER_HZ;
			sample_ce  <= 1'b1;
		end else begin
			sample_acc <= sample_next;
			sample_ce  <= 1'b0;
		end
	end

	// The two 74LS374 latches idle high and drive active-low board controls.
	logic [7:0] lo, hi;
	always_ff @(posedge clk) begin
		if (reset) begin
			lo <= 8'hFF;
			hi <= 8'hFF;
		end else if (wr) begin
			if (sel) hi <= din;
			else     lo <= din;
		end
	end

	wire [7:0] lo_on = ~lo;
	wire [7:0] hi_on = ~hi;
	wire eliminator = (game == GAME_ELIM2) || (game == GAME_ELIM2C)
		|| (game == GAME_ELIM4);
	wire zektor = game == GAME_ZEKTOR;
	wire space_fury = game == GAME_SPACFURY;

	wire noise;
	dsc_noise noise_source(.clk(clk), .reset(reset), .ce(sample_ce), .out(noise));

	wire signed [15:0] elim_audio, fury_audio;
	sega_elim_sound #(.CE_HZ(CE_HZ)) elim_board (
		.clk(clk), .reset(reset || !(eliminator || zektor)), .ce(sample_ce),
		.zektor(zektor), .lo_on(lo_on), .hi_on(hi_on), .noise(noise),
		.ay_a(ay_a), .ay_b(ay_b), .ay_c(ay_c), .audio(elim_audio)
	);

	sega_spacfury_sound #(.CE_HZ(CE_HZ)) fury_board (
		.clk(clk), .reset(reset || !space_fury), .ce(sample_ce),
		.lo_on(lo_on), .hi_on(hi_on), .noise(noise), .audio(fury_audio)
	);

	assign audio = space_fury ? fury_audio
		: (eliminator || zektor) ? elim_audio : 16'sd0;
endmodule

`default_nettype wire
