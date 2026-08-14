//============================================================================
//  Sega G-80 vector field -> framebuffer coordinate map
//
//  Written 2026 by Videodr0me
//
//  The presentation DDA doubles the authentic coordinate grid while retaining
//  every endpoint. Normal presentation uses the hardware source window:
//
//      x  0..2046            doubled full width
//      y  192..1854          doubled 96..927 crop
//
//  Open Matte can retain either source axis outside that window until raster
//  clipping.
//
//  Orientation uses the three per-game configuration flags:
//
//      bit 0  ORIENTATION_FLIP_X
//      bit 1  ORIENTATION_FLIP_Y
//      bit 2  ORIENTATION_SWAP_XY
//
//  Per game:
//      Eliminator, Space Fury, Zektor, Star Trek   FLIP_Y            = 3'b010
//      Tac/Scan   (FLIP_X ^ ROT270)                SWAP|FLIP_Y|FLIP_X= 3'b111
//
//  Scale the oriented field about the raster centre to the active video area.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_geometry (
	input  wire signed [12:0] src_x,
	input  wire signed [12:0] src_y,
	input  wire  [2:0] game_orientation,
	input  wire  [1:0] screen_rotation,
	input  wire  [1:0] open_matte, // {source Y, source X}
	input  wire        mode_240p,

	// Scale numerator over 64; see sega_video.sv for the per-mode values.
	input  wire  [5:0] scale_num,
	input  wire [11:0] center_x,
	input  wire [11:0] center_y,
	input  wire [11:0] render_width,
	input  wire [11:0] render_height,

	output wire [10:0] raster_x,
	output wire [10:0] raster_y,
	output wire        in_bounds
);
	localparam logic signed [12:0] FULL_MAX = 13'sd2046;
	localparam logic signed [12:0] CROP_MAX = 13'sd1662;
	localparam logic signed [12:0] FULL_CTR = 13'sd1022;
	localparam logic signed [12:0] CROP_CTR = 13'sd830;

	wire game_flip_x = game_orientation[0];
	wire game_flip_y = game_orientation[1];
	wire game_swap   = game_orientation[2];

	// Apply the normal source crop; Open Matte can expose either axis.
	wire signed [12:0] sx = src_x;
	wire signed [12:0] sy = src_y - 13'sd192;
	wire source_x_visible = (sx >= 13'sd0) && (sx <= FULL_MAX);
	wire source_y_visible = (sy >= 13'sd0) && (sy <= CROP_MAX);

	// First apply the orientation required by the game, then rotate the
	// resulting upright picture for the user's display.
	wire signed [12:0] game_x_raw = game_swap ? sy : sx;
	wire signed [12:0] game_y_raw = game_swap ? sx : sy;
	wire signed [12:0] game_x_max = game_swap ? CROP_MAX : FULL_MAX;
	wire signed [12:0] game_y_max = game_swap ? FULL_MAX : CROP_MAX;
	wire signed [12:0] game_x_ctr = game_swap ? CROP_CTR : FULL_CTR;
	wire signed [12:0] game_y_ctr = game_swap ? FULL_CTR : CROP_CTR;
	wire signed [12:0] game_x = game_flip_x ?
	                         (game_x_max - game_x_raw) : game_x_raw;
	wire signed [12:0] game_y = game_flip_y ?
	                         (game_y_max - game_y_raw) : game_y_raw;

	logic signed [12:0] oriented_x;
	logic signed [12:0] oriented_y;
	logic signed [12:0] oriented_x_ctr;
	logic signed [12:0] oriented_y_ctr;

	always_comb begin
		case (screen_rotation)
			2'd1: begin
				oriented_x = game_y_max - game_y;
				oriented_y = game_x;
				oriented_x_ctr = game_y_ctr;
				oriented_y_ctr = game_x_ctr;
			end
			2'd2: begin
				oriented_x = game_x_max - game_x;
				oriented_y = game_y_max - game_y;
				oriented_x_ctr = game_x_ctr;
				oriented_y_ctr = game_y_ctr;
			end
			2'd3: begin
				oriented_x = game_y;
				oriented_y = game_x_max - game_x;
				oriented_x_ctr = game_y_ctr;
				oriented_y_ctr = game_x_ctr;
			end
			default: begin
				oriented_x = game_x;
				oriented_y = game_y;
				oriented_x_ctr = game_x_ctr;
				oriented_y_ctr = game_y_ctr;
			end
		endcase
	end

	// Centre, scale by scale_num/64, then re-centre on the raster. In 240p,
	// halve only screen Y so its physical framing matches the 480-line modes.
	// Explicit widths keep signed arithmetic identical across tools.
	wire signed [12:0] a_ctr = oriented_x - oriented_x_ctr;
	wire signed [12:0] b_ctr = oriented_y - oriented_y_ctr;

	// Sign-extend centred coordinates before multiplication.
	wire signed [19:0] a_prod = $signed({{7{a_ctr[12]}}, a_ctr})
	                          * $signed({14'd0, scale_num});
	wire signed [19:0] b_prod = $signed({{7{b_ctr[12]}}, b_ctr})
	                          * $signed({14'd0, scale_num});

	// The low-resolution timings use 720 horizontal samples for a 4:3 image.
	// Expand screen X by 9/8 before truncation to retain the 640-wide framing.
	wire low_res_720 = (render_width == 12'd720) &&
	                   (render_height <= 12'd480);
	wire signed [22:0] a_prod_ext = {{3{a_prod[19]}}, a_prod};
	wire signed [22:0] a_prod_9 = a_prod_ext + (a_prod_ext <<< 3);
	wire signed [20:0] a_out_low =
		$signed({{7{a_prod_9[22]}}, a_prod_9[22:9]});
	wire signed [20:0] a_out = low_res_720 ? a_out_low :
		$signed({a_prod[19], a_prod}) >>> 6;
	wire signed [20:0] b_scaled =
		$signed({b_prod[19], b_prod}) >>> 6;
	wire signed [20:0] b_out = mode_240p ?
		(b_scaled >>> 1) : b_scaled;

	wire signed [20:0] a_pos = a_out + $signed({9'd0, center_x});
	wire signed [20:0] b_pos = b_out + $signed({9'd0, center_y});

	wire a_ok = (a_pos >= 21'sd0) && (a_pos < $signed({9'd0, render_width}));
	wire b_ok = (b_pos >= 21'sd0) && (b_pos < $signed({9'd0, render_height}));

	assign raster_x  = a_ok ? a_pos[10:0] : 11'd0;
	assign raster_y  = b_ok ? b_pos[10:0] : 11'd0;
	assign in_bounds = (open_matte[0] || source_x_visible) &&
	                   (open_matte[1] || source_y_visible) && a_ok && b_ok;

endmodule

`default_nettype wire
