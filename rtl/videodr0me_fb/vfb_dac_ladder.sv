// ============================================================================
// Sega G-80 per-gun 2-bit DAC ladder.
//
// Written 2026 by Videodr0me
//
// The 6.2K/12K ladders on drawing 800-0163 sheet 6 produce nominal levels
//
//     level 0 1 2 3  ->  0, 1/3, 2/3, 1  of full scale
//
// Coefficients 683/2048 and 1365/2048 are within one 10-bit LSB of exact.
// ============================================================================

`default_nettype none

module vfb_dac_ladder (
	input  wire  [9:0] level,     // full-scale DAC value for this pixel
	input  wire  [1:0] sel,       // gun level, 0..3
	output logic [9:0] out
);
	logic [20:0] scaled;
	always_comb begin
		scaled = 21'd0;
		unique case (sel)
			2'd0: out = 10'd0;
			2'd1: begin scaled = level * 21'd683;  out = scaled[20:11]; end
			2'd2: begin scaled = level * 21'd1365; out = scaled[20:11]; end
			2'd3: out = level;
			default: out = 10'd0;
		endcase
	end
endmodule

`default_nettype wire
