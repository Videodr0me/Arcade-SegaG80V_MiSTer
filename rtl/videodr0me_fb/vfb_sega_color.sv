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

	(* romstyle = "M10K" *) logic [9:0] native_level_lut [0:127];
	integer native_level_idx;
	initial begin
		for (native_level_idx = 0; native_level_idx < 128;
		     native_level_idx = native_level_idx + 1)
			// Original formula: floor(intensity * 85 / 32).
			native_level_lut[native_level_idx] =
				10'((native_level_idx * 85) >> 5);
	end

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

	// 6.2K/12K DAC levels use 683/2048 and 1365/2048 for one and two thirds.
	function automatic logic [11:0] ladder_coefficient(input logic [1:0] select);
		begin
			case (select)
				2'd0: ladder_coefficient = 12'd0;
				2'd1: ladder_coefficient = 12'd683;
				2'd2: ladder_coefficient = 12'd1365;
				2'd3: ladder_coefficient = 12'd2048;
				default: ladder_coefficient = 12'd0;
			endcase
		end
	endfunction

	logic [12:0] sample_s1;
	logic [1:0]  tone_s1;
	logic [9:0]  level_s1;
	wire sample_active = (vfb_sample_color(canonical_in) != 6'd0) &&
	                     (vfb_sample_intensity(canonical_in) != 7'd0);

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s1 <= sample_active ? canonical_in : 13'd0;
			tone_s1 <= tone_mapping;
			level_s1 <= native_level_lut[vfb_sample_intensity(canonical_in)];
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
	logic [11:0] red_coeff_s3;
	logic [11:0] green_coeff_s3;
	logic [11:0] blue_coeff_s3;
	wire [5:0] color_s2 = vfb_sample_color(sample_s2);
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s3 <= sample_s2;
			tone_level_s3 <= tone_level_comb;
			red_coeff_s3 <= ladder_coefficient(color_s2[5:4]);
			green_coeff_s3 <= ladder_coefficient(color_s2[3:2]);
			blue_coeff_s3 <= ladder_coefficient(color_s2[1:0]);
		end
	end

	wire [21:0] red_ladder_product = tone_level_s3 * red_coeff_s3;
	wire [21:0] green_ladder_product = tone_level_s3 * green_coeff_s3;
	wire [21:0] blue_ladder_product = tone_level_s3 * blue_coeff_s3;

	logic [12:0] sample_s4;
	logic [9:0]  red_ladder_s4;
	logic [9:0]  green_ladder_s4;
	logic [9:0]  blue_ladder_s4;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			sample_s4 <= sample_s3;
			red_ladder_s4 <= red_ladder_product[20:11];
			green_ladder_s4 <= green_ladder_product[20:11];
			blue_ladder_s4 <= blue_ladder_product[20:11];
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
