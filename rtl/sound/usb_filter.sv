//============================================================================
//  Sega Universal Sound Board analog chain
//
//  Improved by Videodr0me from schematics.
//
//  Fixed-point model of the filter and mix network on Universal Sound Board
//  drawing 800-0377. The MM5837 noise path uses the five poles obtained from
//  the sheet 6 component network rather than MAME's three-pole approximation.
//  Their Q10 mix weights sum to zero exactly, preserving the network's DC
//  rejection. Timers, envelopes, switched gates, and final coupling retain
//  the board topology and evaluation order.
//
//  Arithmetic: 32-bit signed Q8.24 (range +/-128.0, resolution 6e-8).
//
//  One-pole coefficients are signed power-of-two sums, so the filters need no
//  additional multipliers. At the board's 2 MHz stream rate:
//
//    chan CR    (10k,1u)     0.000049999   >>14 - >>16 + >>18 + >>21   0.14%
//    gate1 slow (100k,.01u)  0.000499875   >>11 + >>16 - >>18          0.03%
//    gate1 fast (1k,.01u)    0.048770575    >>4 -  >>6 +  >>9          0.12%
//    gate2 slow (200k,.01u)  0.000249969   >>12 + >>17 - >>19          0.04%
//    gate2 fast (2k,.01u)    0.024690088    >>5 -  >>7 + >>10 + >>12   0.13%
//    final CR   (100k,4.7u)  0.000001064   >>20 + >>23 - >>26          0.55%
//
//  The schematic noise poles are 24.15, 49.13, 203.77, 1293.93, and
//  13622.48 Hz. Their partial-fraction weights, including the common 1 kHz
//  level match, are rounded to Q10 as -11217, 3549, 5479, 1477, and 712.
//
//  Only the three envelope DAC gains need real multipliers (the envelope is
//  an 8-bit value written by the 8035), and the sequencer shares one set of
//  them across the three groups.
//
//  Each 2 MHz sample uses seven clocks: pole update, two noise-mix stages,
//  three channel groups, and final mix. Consecutive ticks are at least seven
//  clocks apart in the 15.46848 MHz machine domain.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module usb_filter (
	input  wire        clk,
	input  wire        reset,
	input  wire        tick,          // 2 MHz stream tick

	input  wire        noise_in,      // MM5837 state
	input  wire  [2:0] tmr0,          // 8253 outputs, one group per port
	input  wire  [2:0] tmr1,
	input  wire  [2:0] tmr2,
	input  wire  [7:0] env0_0, env0_1, env0_2,
	input  wire  [7:0] env1_0, env1_1, env1_2,
	input  wire  [7:0] env2_0, env2_1, env2_2,
	input  wire  [2:0] cfg,           // per-group envelope mode

	output logic signed [15:0] audio
);
	localparam int W = 32;                                  // Q8.24
	localparam logic signed [W-1:0] ONE = 32'sh0100_0000;

	// ------------------------------------------------------------------
	// Filter coefficients, as signed shift-add sums of the delta
	// ------------------------------------------------------------------
	function automatic logic signed [W-1:0] e_chan(input logic signed [W-1:0] d);
		e_chan = (d >>> 14) - (d >>> 16) + (d >>> 18) + (d >>> 21);
	endfunction
	function automatic logic signed [W-1:0] e_g1_slow(input logic signed [W-1:0] d);
		e_g1_slow = (d >>> 11) + (d >>> 16) - (d >>> 18);
	endfunction
	function automatic logic signed [W-1:0] e_g1_fast(input logic signed [W-1:0] d);
		e_g1_fast = (d >>> 4) - (d >>> 6) + (d >>> 9);
	endfunction
	function automatic logic signed [W-1:0] e_g2_slow(input logic signed [W-1:0] d);
		e_g2_slow = (d >>> 12) + (d >>> 17) - (d >>> 19);
	endfunction
	function automatic logic signed [W-1:0] e_g2_fast(input logic signed [W-1:0] d);
		e_g2_fast = (d >>> 5) - (d >>> 7) + (d >>> 10) + (d >>> 12);
	endfunction
	function automatic logic signed [W-1:0] e_final(input logic signed [W-1:0] d);
		e_final = (d >>> 20) + (d >>> 23) - (d >>> 26);
	endfunction
	function automatic logic signed [W-1:0] e_np0(input logic signed [W-1:0] d);
		e_np0 = (d >>> 14) + (d >>> 16) - (d >>> 21) + (d >>> 25);
	endfunction
	function automatic logic signed [W-1:0] e_np1(input logic signed [W-1:0] d);
		e_np1 = (d >>> 13) + (d >>> 15) + (d >>> 19)
		      - (d >>> 23) - (d >>> 24);
	endfunction
	function automatic logic signed [W-1:0] e_np2(input logic signed [W-1:0] d);
		e_np2 = (d >>> 11) + (d >>> 13) + (d >>> 15) - (d >>> 20);
	endfunction
	function automatic logic signed [W-1:0] e_np3(input logic signed [W-1:0] d);
		e_np3 = (d >>> 8) + (d >>> 13) + (d >>> 15) - (d >>> 19);
	endfunction
	function automatic logic signed [W-1:0] e_np4(input logic signed [W-1:0] d);
		e_np4 = (d >>> 5) + (d >>> 7) + (d >>> 9) + (d >>> 10)
		      - (d >>> 13) + (d >>> 16) + (d >>> 17);
	endfunction

	// 1.56x amplifier: 1 + 1/2 + 1/16 = 1.5625, 0.16% high
	function automatic logic signed [W-1:0] gain156(input logic signed [W-1:0] x);
		gain156 = x + (x >>> 1) + (x >>> 4);
	endfunction

	// ------------------------------------------------------------------
	// Noise source: five parallel poles from the schematic network.
	// ------------------------------------------------------------------
	logic signed [W-1:0] npole [0:4];
	logic signed [W-1:0] nsum_a, nsum_b, nsum_c;
	logic signed [W-1:0] nv;

	wire signed [W-1:0] ns = noise_in ? ONE : 32'sd0;
	wire signed [W-1:0] npole_n [0:4];
	assign npole_n[0] = npole[0] + e_np0(ns - npole[0]);
	assign npole_n[1] = npole[1] + e_np1(ns - npole[1]);
	assign npole_n[2] = npole[2] + e_np2(ns - npole[2]);
	assign npole_n[3] = npole[3] + e_np3(ns - npole[3]);
	assign npole_n[4] = npole[4] + e_np4(ns - npole[4]);

	// Q10 partial-fraction weights. Shift/add form keeps this network out of
	// the DSP blocks used by the envelope DACs.
	function automatic logic signed [W-1:0] mix_np0(input logic signed [W-1:0] x);
		mix_np0 = -(x <<< 4) + (x <<< 2) + x + (x >>> 4)
		        - (x >>> 6) - (x >>> 10);
	endfunction
	function automatic logic signed [W-1:0] mix_np1(input logic signed [W-1:0] x);
		mix_np1 = (x <<< 2) - (x >>> 1) - (x >>> 5)
		        - (x >>> 8) + (x >>> 10);
	endfunction
	function automatic logic signed [W-1:0] mix_np2(input logic signed [W-1:0] x);
		mix_np2 = (x <<< 3) - (x <<< 1) - (x >>> 1) - (x >>> 3)
		        - (x >>> 5) + (x >>> 7) - (x >>> 10);
	endfunction
	function automatic logic signed [W-1:0] mix_np3(input logic signed [W-1:0] x);
		mix_np3 = (x <<< 1) - (x >>> 1) - (x >>> 4)
		        + (x >>> 8) + (x >>> 10);
	endfunction
	function automatic logic signed [W-1:0] mix_np4(input logic signed [W-1:0] x);
		mix_np4 = x - (x >>> 2) - (x >>> 4) + (x >>> 7);
	endfunction

	// ------------------------------------------------------------------
	// Per-group state and inputs
	// ------------------------------------------------------------------
	logic signed [W-1:0] cf0 [0:2];
	logic signed [W-1:0] cf1 [0:2];
	logic signed [W-1:0] gt1 [0:2];
	logic signed [W-1:0] gt2 [0:2];
	logic signed [W-1:0] fin;
	logic signed [W-1:0] acc;

	logic  [2:0] st;
	logic        busy;

	// State 0 runs on the tick cycle itself.
	wire       run    = tick | busy;
	wire [2:0] st_cur = tick ? 3'd0 : st;

	// States 3..5 select group 0..2; other states park on group 0 so the
	// array indices below always stay in range.
	wire [1:0] grp = (st_cur == 3'd4) ? 2'd1 : (st_cur == 3'd5) ? 2'd2 : 2'd0;

	wire [2:0] tsel  = (grp == 2'd0) ? tmr0 : (grp == 2'd1) ? tmr1 : tmr2;
	wire [7:0] ev0   = (grp == 2'd0) ? env0_0 : (grp == 2'd1) ? env1_0 : env2_0;
	wire [7:0] ev1   = (grp == 2'd0) ? env0_1 : (grp == 2'd1) ? env1_1 : env2_1;
	wire [7:0] ev2   = (grp == 2'd0) ? env0_2 : (grp == 2'd1) ? env1_2 : env2_2;
	wire       cfg_g = cfg[grp];

	// ------------------------------------------------------------------
	// Envelope DAC gains. These are the only multipliers in the module.
	// 1/100 as >>7 + >>9 + >>12 (0.098% high), 1/33 as >>5 - >>10 (0.098%).
	// ------------------------------------------------------------------
	function automatic logic signed [W-1:0] dac100(
			input logic signed [W-1:0] x, input logic [7:0] e);
		logic signed [W+8:0] p;
		begin
			p = $signed(x) * $signed({1'b0, e});
			dac100 = W'((p >>> 7) + (p >>> 9) + (p >>> 12));
		end
	endfunction
	function automatic logic signed [W-1:0] dac33(
			input logic signed [W-1:0] x, input logic [7:0] e);
		logic signed [W+8:0] p;
		begin
			p = $signed(x) * $signed({1'b0, e});
			dac33 = W'((p >>> 5) - (p >>> 10));
		end
	endfunction

	// ---- channels 0 and 1: CR filter the 8253 square wave, then scale ----
	wire signed [W-1:0] sq0 = tsel[0] ? ONE : 32'sd0;
	wire signed [W-1:0] sq1 = tsel[1] ? ONE : 32'sd0;
	wire signed [W-1:0] cr0 = sq0 - cf0[grp];
	wire signed [W-1:0] cr1 = sq1 - cf1[grp];
	wire signed [W-1:0] c0  = dac100(cr0, ev0);
	wire signed [W-1:0] c1  = dac100(cr1, ev1);

	// ---- channel 2: the switched gate filters -------------------------
	// Channel 2 selects both RC time constants from the timer output. The two
	// poles are evaluated in series within one sample, and their new values feed
	// the current mix.
	function automatic logic signed [W-1:0] step_g1(
			input logic signed [W-1:0] cap, input logic signed [W-1:0] x,
			input logic fast);
		step_g1 = cap + (fast ? e_g1_fast(x - cap) : e_g1_slow(x - cap));
	endfunction
	function automatic logic signed [W-1:0] step_g2(
			input logic signed [W-1:0] cap, input logic signed [W-1:0] x,
			input logic fast);
		step_g2 = cap + (fast ? e_g2_fast(x - cap) : e_g2_slow(x - cap));
	endfunction

	// config 0: noise -> switched RC -> 1.56x -> invert -> DAC -> 33k -> mix
	wire signed [W-1:0] a_g1 = step_g1(gt1[grp], nv, tsel[2]);
	wire signed [W-1:0] a_g2 = step_g2(gt2[grp], a_g1, tsel[2]);
	wire signed [W-1:0] a_c2 = -gain156(dac33(a_g2, ev2));
	wire signed [W-1:0] a_mix = c0 + c1 + a_c2;

	// config 1: noise -> invert -> DAC -> 33k -> mix -> invert -> RC -> 1.56x
	wire signed [W-1:0] b_c2  = -dac33(nv, ev2);
	wire signed [W-1:0] b_pre = c0 + c1 + b_c2;
	wire signed [W-1:0] b_g1  = step_g1(gt1[grp], -b_pre, tsel[2]);
	wire signed [W-1:0] b_g2  = step_g2(gt2[grp], b_g1, tsel[2]);
	wire signed [W-1:0] b_mix = gain156(b_g2);

	wire signed [W-1:0] mix   = cfg_g ? b_mix : a_mix;
	wire signed [W-1:0] g1_n  = cfg_g ? b_g1  : a_g1;
	wire signed [W-1:0] g2_n  = cfg_g ? b_g2  : a_g2;

	// ---- final mix: CR filter, 0.1 trim, then to 16-bit ---------------
	wire signed [W-1:0] fin_out = acc - fin;
	// * 0.1, as 1/8 - 1/32 + 1/128 - 1/512 = 0.099609
	wire signed [W-1:0] scaled  = (fin_out >>> 3) - (fin_out >>> 5)
	                            + (fin_out >>> 7) - (fin_out >>> 9);
	// A nominal 1.0 maps to a quarter of 16-bit full scale, leaving 12 dB of
	// headroom. The schematic model reaches 3.50 on a worst-case stimulus with
	// all nine envelope DACs driven randomly at full scale (see
	// sim/audio/tb/tb_usb_filter.cpp), so mapping
	// 1.0 to full scale would clip the board's own peaks. The core's mixer
	// sets the final level.
	wire signed [W-1:0] shifted = scaled >>> 11;
	wire signed [15:0]  clamped = (shifted >  32767) ?  16'sh7FFF :
	                              (shifted < -32768) ? -16'sh8000 :
	                                                    shifted[15:0];

	// ------------------------------------------------------------------
	integer i;
	always_ff @(posedge clk) begin
		if (reset) begin
			for (i = 0; i < 5; i = i + 1) npole[i] <= '0;
			nsum_a <= '0; nsum_b <= '0; nsum_c <= '0; nv <= '0;
			fin <= '0; acc <= '0; audio <= 16'sd0;
			st  <= 3'd0; busy <= 1'b0;
			for (i = 0; i < 3; i = i + 1) begin
				cf0[i] <= '0; cf1[i] <= '0; gt1[i] <= '0; gt2[i] <= '0;
			end
		end else begin
			if (run) begin
				st   <= st_cur + 3'd1;
				busy <= (st_cur != 3'd6);
			end

			if (run) begin
				unique case (st_cur)
					3'd0: begin                       // noise poles
						for (i = 0; i < 5; i = i + 1) npole[i] <= npole_n[i];
					end
					3'd1: begin                       // weighted pole pairs
						nsum_a <= mix_np0(npole[0]) + mix_np1(npole[1]);
						nsum_b <= mix_np2(npole[2]) + mix_np3(npole[3]);
						nsum_c <= mix_np4(npole[4]);
					end
					3'd2: begin                       // noise sum
						nv  <= nsum_a + nsum_b + nsum_c;
						acc <= '0;
					end
					3'd3, 3'd4, 3'd5: begin           // one group per clock
						cf0[grp] <= cf0[grp] + e_chan(cr0);
						cf1[grp] <= cf1[grp] + e_chan(cr1);
						gt1[grp] <= g1_n;
						gt2[grp] <= g2_n;
						acc      <= acc + mix;
					end
					3'd6: begin                       // final mix
						fin   <= fin + e_final(fin_out);
						audio <= clamped;
					end
					default: ;
				endcase
			end
		end
	end

endmodule

`default_nettype wire
