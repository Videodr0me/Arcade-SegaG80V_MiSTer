//============================================================================
//  Per-game configuration for the Sega G-80 X-Y core.
//
//  The MRA supplies a supported-game identifier at ioctl_index 1. Security,
//  sound, controls, and orientation are derived from it here.
//
//  Cross-checked against MAME segag80v.cpp and the Sega schematics.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`ifndef SEGA_GAME_PKG_SV
`define SEGA_GAME_PKG_SV

package sega_game_pkg;
	localparam logic [2:0] GAME_ELIM2    = 3'd0;
	localparam logic [2:0] GAME_ELIM4    = 3'd1;
	localparam logic [2:0] GAME_SPACFURY = 3'd2;
	localparam logic [2:0] GAME_ZEKTOR   = 3'd3;
	localparam logic [2:0] GAME_TACSCAN  = 3'd4;
	localparam logic [2:0] GAME_STARTREK = 3'd5;
	localparam logic [2:0] GAME_ELIM2C   = 3'd6;
endpackage

`default_nettype none

module sega_game_cfg (
	input  wire  [2:0] game,
	output logic [2:0] cfg_chip,     // sega_security_pkg id
	output logic       cfg_usb,      // Universal Sound Board RAM at $D000
	output logic       cfg_speech,   // speech board fitted
	output logic [1:0] cfg_fc,       // 0 = plain port, 1 = spinner, 2 = elim4
	output logic [2:0] cfg_orient,   // {swap_xy, flip_y, flip_x}
	output wire        cfg_open_matte,
	output wire  [1:0] cfg_matte_axes // {source Y, source X}
);
	// Open Matte availability by game ID.
	localparam logic [7:0] OPEN_MATTE_GAMES = 8'b0111_1111;
	// Eliminator opens only source Y; off-window X vectors are not display data.
	wire eliminator = (game == sega_game_pkg::GAME_ELIM2) ||
	                  (game == sega_game_pkg::GAME_ELIM4) ||
	                  (game == sega_game_pkg::GAME_ELIM2C);
	assign cfg_matte_axes = !OPEN_MATTE_GAMES[game] ? 2'b00 :
	                        eliminator ? 2'b10 : 2'b11;
	assign cfg_open_matte = |cfg_matte_axes;

	// sega_security_pkg: 3 = 315-0064, 4 = 315-0070, 5 = 315-0076, 6 = 315-0082
	always_comb begin
		unique case (game)
		sega_game_pkg::GAME_ELIM2,
		sega_game_pkg::GAME_ELIM2C:
			begin cfg_chip=3'd4; cfg_usb=1'b0; cfg_speech=1'b0; cfg_fc=2'd0; cfg_orient=3'b010; end
		sega_game_pkg::GAME_ELIM4:
			begin cfg_chip=3'd5; cfg_usb=1'b0; cfg_speech=1'b0; cfg_fc=2'd2; cfg_orient=3'b010; end
		sega_game_pkg::GAME_SPACFURY:
			begin cfg_chip=3'd3; cfg_usb=1'b0; cfg_speech=1'b1; cfg_fc=2'd0; cfg_orient=3'b010; end
		sega_game_pkg::GAME_ZEKTOR:
			begin cfg_chip=3'd6; cfg_usb=1'b0; cfg_speech=1'b1; cfg_fc=2'd1; cfg_orient=3'b010; end
		sega_game_pkg::GAME_TACSCAN:
			// ORIENTATION_FLIP_X ^ ROT270 = SWAP_XY | FLIP_Y | FLIP_X
			begin cfg_chip=3'd5; cfg_usb=1'b1; cfg_speech=1'b0; cfg_fc=2'd1; cfg_orient=3'b111; end
		sega_game_pkg::GAME_STARTREK:
			begin cfg_chip=3'd3; cfg_usb=1'b1; cfg_speech=1'b1; cfg_fc=2'd1; cfg_orient=3'b010; end
		default:
			begin cfg_chip=3'd0; cfg_usb=1'b0; cfg_speech=1'b0; cfg_fc=2'd0; cfg_orient=3'b010; end
		endcase
	end
endmodule

`default_nettype wire

`endif
