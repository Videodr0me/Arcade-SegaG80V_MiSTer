//============================================================================
//  Sega speech board output filter
//
//  Models the passive network and TL081 stage between the SP0250 and CD4053.
//  Component values follow drawing 800-0294 rev H sheet 5.
//
//  Topology:
//
//    SP0250 --| |--/\/\/--+--------+-------> U8.3   (TL081, non-inverting)
//              C9   R18   |        |
//            0.1u   22k  R19      C10             gain = 1 + R21/R20
//                       270k    0.047u                 = 1 + 10k/4.7k
//                         |        |                   = 3.128
//                        GND      GND
//
//  That is two cascaded one-poles plus a gain:
//
//    C9  with R18+R19        DC block   tau 29.2 ms    5.45 Hz
//    C10 with R18||R19       low pass   tau 956 us     166.5 Hz
//    R19/(R18+R19) x (1 + R21/R20)      gain 0.9247 x 3.1277 = 2.8920
//
//  R19 is 270K and R20 is 4.7K on drawing 800-0294 rev H sheet 5.
//
//  C50 is omitted because the preceding 166.5 Hz pole strongly attenuates its
//  5.3-16.6 kHz shelf.
//
//  Every coefficient is a sum of at most four signed powers of two, so this
//  needs no multipliers. Run at the 3.12 MHz board clock, so it filters the
//  held DAC waveform the way the real network does, steps and all:
//
//    C9  DC block   e=1.09764e-05   >>16 - >>18 - >>21          0.08%
//    C10 low pass   e=3.35175e-04   >>11 - >>13 - >>15          0.15%
//    gain 2.8920                    <<2 - <<0 - >>3 + >>6       0.05%
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module speech_filter #(
	// 1 selects a 0.0047u C10 comparison value instead of the board's 0.047u.
	parameter bit C10_TENTH = 1'b0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,              // 3.12 MHz speech board clock

	input  wire signed [7:0] dac,       // SP0250 output, held between samples
	output wire signed [15:0] audio
);
	localparam int W = 32;

	// The DAC is +/-63, carried 16 bits up so the smallest filter step
	// (a delta shifted right 23) is still meaningful.
	wire signed [W-1:0] x = {{8{dac[7]}}, dac, 16'd0};

	logic signed [W-1:0] cap_hp, cap_lp;

	// C9 high pass; cap_hp tracks DC.
	wire signed [W-1:0] hp = x - cap_hp;
	wire signed [W-1:0] e_hp = (hp >>> 16) - (hp >>> 18) - (hp >>> 21);

	// C10: step_rc
	wire signed [W-1:0] d_lp = hp - cap_lp;
	wire signed [W-1:0] e_lp = (d_lp >>> 11) - (d_lp >>> 13) - (d_lp >>> 15);
	// C10/10 variant, 1675 Hz: e = 3.3665e-03
	wire signed [W-1:0] e_lp_f = (d_lp >>> 8) - (d_lp >>> 11) - (d_lp >>> 14);

	always_ff @(posedge clk) begin
		if (reset) begin
			cap_hp <= '0;
			cap_lp <= '0;
		end else if (ce) begin
			cap_hp <= cap_hp + e_hp;
			cap_lp <= cap_lp + (C10_TENTH ? e_lp_f : e_lp);
		end
	end

	// 0.9247 divider x 3.1277 op-amp = 2.8920, as 4 - 1 - 1/8 + 1/64
	wire signed [W-1:0] y = (cap_lp <<< 2) - cap_lp - (cap_lp >>> 3)
	                      + (cap_lp >>> 6);

	// Return to the unfiltered path's scale.
	wire signed [W-1:0] o = y >>> 8;
	assign audio = (o >  32767) ?  16'sh7FFF :
	               (o < -32768) ? -16'sh8000 : o[15:0];

endmodule

`default_nettype wire
