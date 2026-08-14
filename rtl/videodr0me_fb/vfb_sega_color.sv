// ============================================================================
// Sega G-80 canonical pixel to RGB conversion.
// ============================================================================

`default_nettype none

module vfb_sega_color (
	input  wire         clk_sys,
	input  wire         ce_pix,
	input  wire  [12:0] canonical_in,
	input  wire   [1:0] tone_mapping,
	output logic [12:0] canonical_out,
	output logic [7:0]  red,
	output logic [7:0]  green,
	output logic [7:0]  blue
);

	import vfb_layout_pkg::*;

	localparam logic [1:0] TONE_LINEAR1 = 2'd0;
	localparam logic [1:0] TONE_LINEAR2 = 2'd1;
	localparam logic [1:0] TONE_BRIGHT  = 2'd2;

	function automatic logic [9:0] native_level(input logic [6:0] intensity);
		logic [13:0] scaled;
		begin
			// 96 * 85 / 32 = 255. Values above 96 retain crossing headroom.
			scaled = ({7'd0, intensity} << 6) +
			         ({7'd0, intensity} << 4) +
			         ({7'd0, intensity} << 2) +
			          {7'd0, intensity};
			native_level = scaled[13:5];
		end
	endfunction

	function automatic logic [7:0] add_spill(
		input logic [9:0] level,
		input logic [5:0] spill
	);
		logic [10:0] sum;
		begin
			sum = {1'b0, level} + {5'd0, spill};
			if ((level >= 10'd255) || (sum > 11'd255))
				add_spill = 8'd255;
			else
				add_spill = sum[7:0];
		end
	endfunction

	logic [12:0] sample_s1;
	logic [1:0]  tone_s1;
	logic [9:0]  level_s1;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s1 <= canonical_in;
			tone_s1 <= tone_mapping;
			level_s1 <= native_level(vfb_sample_intensity(canonical_in));
		end
	end

	logic [8:0]  curve_coefficient_comb;
	logic [18:0] curve_product_comb;
	logic [13:0] fine_scaled_comb;
	logic [9:0]  fine_comb;
	logic [9:0]  shoulder_room_comb;
	logic [9:0]  shoulder_comb;

	always_comb begin
		curve_coefficient_comb = (tone_s1 == TONE_LINEAR1) ? 9'd311 : 9'd389;
		curve_product_comb = level_s1 * curve_coefficient_comb;
		fine_scaled_comb = ({4'd0, level_s1} << 3) +
		                   ({4'd0, level_s1} << 2) +
		                    {4'd0, level_s1} + 14'd32;
		fine_comb = fine_scaled_comb[13:6];
		shoulder_room_comb = (level_s1 > 10'd203) ? level_s1 - 10'd203 : 10'd0;
		shoulder_comb = (shoulder_room_comb < fine_comb) ?
		                  shoulder_room_comb : fine_comb;
	end

	logic [12:0] sample_s2;
	logic [1:0]  tone_s2;
	logic [9:0]  level_s2;
	logic [18:0] curve_product_s2;
	logic [9:0]  shoulder_s2;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s2 <= sample_s1;
			tone_s2 <= tone_s1;
			level_s2 <= level_s1;
			curve_product_s2 <= curve_product_comb;
			shoulder_s2 <= shoulder_comb;
		end
	end

	logic [9:0] tone_level_comb;
	always_comb begin
		case (tone_s2)
			TONE_LINEAR1,
			TONE_LINEAR2: tone_level_comb = curve_product_s2[17:8];
			TONE_BRIGHT: tone_level_comb =
				(vfb_sample_intensity(sample_s2) > VFB_BEAM_INTENSITY) ?
				level_s2 : level_s2 + shoulder_s2;
			default: tone_level_comb = level_s2;
		endcase
		if ((vfb_sample_color(sample_s2) == 6'd0) ||
		    (vfb_sample_intensity(sample_s2) == 7'd0))
			tone_level_comb = 10'd0;
	end

	logic [12:0] sample_s3;
	logic [9:0]  tone_level_s3;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s3 <= sample_s2;
			tone_level_s3 <= tone_level_comb;
		end
	end

	wire [9:0] red_ladder_comb;
	wire [9:0] green_ladder_comb;
	wire [9:0] blue_ladder_comb;
	wire [5:0] color_s3 = vfb_sample_color(sample_s3);

	vfb_dac_ladder red_dac (
		.level(tone_level_s3),
		.sel(color_s3[5:4]),
		.out(red_ladder_comb)
	);
	vfb_dac_ladder green_dac (
		.level(tone_level_s3),
		.sel(color_s3[3:2]),
		.out(green_ladder_comb)
	);
	vfb_dac_ladder blue_dac (
		.level(tone_level_s3),
		.sel(color_s3[1:0]),
		.out(blue_ladder_comb)
	);

	logic [12:0] sample_s4;
	logic [9:0]  red_ladder_s4;
	logic [9:0]  green_ladder_s4;
	logic [9:0]  blue_ladder_s4;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s4 <= sample_s3;
			red_ladder_s4 <= red_ladder_comb;
			green_ladder_s4 <= green_ladder_comb;
			blue_ladder_s4 <= blue_ladder_comb;
		end
	end

	logic [9:0]  red_excess;
	logic [9:0]  green_excess;
	logic [9:0]  blue_excess;
	logic [11:0] excess_sum;
	logic [1:0]  spill_targets;
	logic [11:0] spill_share;
	logic [5:0]  spill;
	logic [7:0]  red_spilled;
	logic [7:0]  green_spilled;
	logic [7:0]  blue_spilled;

	always_comb begin
		// Share clipped DAC energy among channels below full scale.
		red_excess = (red_ladder_s4 > 10'd255) ?
			red_ladder_s4 - 10'd255 : 10'd0;
		green_excess = (green_ladder_s4 > 10'd255) ?
			green_ladder_s4 - 10'd255 : 10'd0;
		blue_excess = (blue_ladder_s4 > 10'd255) ?
			blue_ladder_s4 - 10'd255 : 10'd0;
		excess_sum = {2'd0, red_excess} +
		             {2'd0, green_excess} +
		             {2'd0, blue_excess};

		spill_targets = 2'd0;
		if (red_ladder_s4 < 10'd255)
			spill_targets = spill_targets + 1'd1;
		if (green_ladder_s4 < 10'd255)
			spill_targets = spill_targets + 1'd1;
		if (blue_ladder_s4 < 10'd255)
			spill_targets = spill_targets + 1'd1;

		case (spill_targets)
			2'd1: spill_share = excess_sum;
			2'd2: spill_share = excess_sum >> 1;
			default: spill_share = 12'd0;
		endcase
		spill = (spill_share > 12'd32) ? 6'd32 : spill_share[5:0];

		red_spilled = add_spill(red_ladder_s4, spill);
		green_spilled = add_spill(green_ladder_s4, spill);
		blue_spilled = add_spill(blue_ladder_s4, spill);
	end

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			canonical_out <= sample_s4;
			red <= red_spilled;
			green <= green_spilled;
			blue <= blue_spilled;
		end
	end

endmodule

`default_nettype wire
