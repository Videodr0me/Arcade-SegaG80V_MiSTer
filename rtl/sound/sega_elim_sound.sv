//============================================================================
//  Sega Eliminator and Zektor sound board
//
//  Written by Videodr0me
//
//  Oscillators, RC poles, divider taps, and final mixing follow Sega drawing
//  800-3174 and MAME's nl_elim.cpp netlist.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

// The torpedo one-shot enables a descending VCO for about 300 ms. Its output
// clocks the board's weighted CD4024 divider.
module sega_elim_torpedo (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire               gate,
	output wire signed [15:0] out
);
	logic gate_q, pending, active, restart;
	logic [8:0] sample_count;
	logic [4:0] sweep_step;
	logic [15:0] freq_hz;

	always_comb begin
		case (sweep_step)
			 0: freq_hz = 16'd9000;
			 1: freq_hz = 16'd7600;
			 2: freq_hz = 16'd6500;
			 3: freq_hz = 16'd5600;
			 4: freq_hz = 16'd4900;
			 5: freq_hz = 16'd4300;
			 6: freq_hz = 16'd3800;
			 7: freq_hz = 16'd3400;
			 8: freq_hz = 16'd3100;
			 9: freq_hz = 16'd2850;
			10: freq_hz = 16'd2750;
			11: freq_hz = 16'd2650;
			12: freq_hz = 16'd2500;
			13: freq_hz = 16'd2350;
			14: freq_hz = 16'd2200;
			15: freq_hz = 16'd2050;
			16: freq_hz = 16'd2000;
			17: freq_hz = 16'd1970;
			18: freq_hz = 16'd1940;
			19: freq_hz = 16'd1850;
			20: freq_hz = 16'd1775;
			21: freq_hz = 16'd1700;
			22: freq_hz = 16'd1620;
			23: freq_hz = 16'd1540;
			24: freq_hz = 16'd1460;
			25: freq_hz = 16'd1200;
			26: freq_hz = 16'd800;
			27: freq_hz = 16'd500;
			28: freq_hz = 16'd400;
			29: freq_hz = 16'd350;
			30: freq_hz = 16'd320;
			default: freq_hz = 16'd300;
		endcase
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			gate_q       <= 1'b0;
			pending      <= 1'b0;
			active       <= 1'b0;
			restart      <= 1'b0;
			sample_count <= '0;
			sweep_step   <= '0;
		end else begin
			gate_q <= gate;
			if (gate && !gate_q) pending <= 1'b1;
			if (ce) begin
				restart <= 1'b0;
				if (pending || (gate && !gate_q)) begin
					pending      <= 1'b0;
					active       <= 1'b1;
					restart      <= 1'b1;
					sample_count <= '0;
					sweep_step   <= '0;
				end else if (active) begin
					if (sample_count == 9'd449) begin
						sample_count <= '0;
						if (sweep_step == 5'd31)
							active <= 1'b0;
						else
							sweep_step <= sweep_step + 1'd1;
					end else begin
						sample_count <= sample_count + 1'd1;
					end
				end
			end
		end
	end

	logic [15:0] torp_env;
	wire [16:0] torp_env_rise = {1'b0, 16'hFFFF - torp_env} >> 6;
	wire [15:0] torp_env_fall = torp_env >> 7;

	always_ff @(posedge clk) begin
		if (reset) begin
			torp_env <= 16'd0;
		end else if (ce) begin
			if (active) begin
				if (torp_env != 16'hFFFF)
					torp_env <= torp_env + ((torp_env_rise != 0) ? torp_env_rise[15:0] : 16'd1);
			end else if (torp_env != 16'd0) begin
				torp_env <= (torp_env > torp_env_fall) ? torp_env - ((torp_env_fall != 0) ? torp_env_fall : 16'd1) : 16'd0;
			end
		end
	end

	wire signed [15:0] divider_out;
	dsc_swept_divider divider (
		.clk(clk), .reset(reset), .ce(ce), .restart(restart),
		.freq_hz(freq_hz), .out(divider_out)
	);

	dsc_vca torp_vca (
		.signal(divider_out),
		.gain(torp_env),
		.out(out)
	);
endmodule

module sega_elim_sound #(
	parameter int CE_HZ  = 48_000
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        zektor,
	input  wire  [7:0] lo_on,
	input  wire  [7:0] hi_on,
	input  wire        noise,
	input  wire  [7:0] ay_a,
	input  wire  [7:0] ay_b,
	input  wire  [7:0] ay_c,
	output wire signed [15:0] audio
);
	function automatic [31:0] hz_inc(input integer hz);
		hz_inc = mhz_inc(hz * 1000);
	endfunction

	function automatic [31:0] mhz_inc(input integer mhz);
		logic [63:0] scaled;
		begin
			scaled = (64'd4294967296 * 64'(mhz)) / (64'(CE_HZ) * 64'd1000);
			mhz_inc = scaled[31:0];
		end
	endfunction

	function automatic [15:0] amp_2bit(input [1:0] value);
		case (value)
			2'd0: amp_2bit = 16'h0000;
			2'd1: amp_2bit = 16'h5555;
			2'd2: amp_2bit = 16'hAAAA;
			default: amp_2bit = 16'hFFFF;
		endcase
	endfunction

	function automatic signed [25:0] sx16(input signed [15:0] value);
		sx16 = {{10{value[15]}}, value};
	endfunction

	wire signed [15:0] noise_raw = noise ? 16'sd24576 : -16'sd24576;

	// Fixed board oscillators. The two 218 Hz clocks are intentionally detuned.
	wire osc_10, osc_70, osc_121, osc_218a, osc_218b;
	wire [15:0] mod_35;
	dsc_osc o10   (.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(10580)),  .square(osc_10));
	dsc_osc o70   (.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(69580)),  .square(osc_70));
	dsc_osc o121  (.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(121120)), .square(osc_121));
	dsc_osc o218a (.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(218010)), .square(osc_218a));
	dsc_osc o218b (.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(217980)), .square(osc_218b));
	dsc_triangle m35(.clk(clk), .reset(reset), .ce(ce), .inc(hz_inc(35)), .wave(mod_35));

	// The explosion channels use the board's two-pole noise filters.
	wire signed [15:0] ex1_f1, ex1_src;
	wire signed [15:0] ex2_f1, ex2_src;
	wire signed [15:0] ex3_f1, ex3_src;
	dsc_lpf #(.S0(6), .S1(8),  .S2(10)) ex1_p1 (.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(ex1_f1));
	dsc_lpf #(.S0(8), .S1(11), .S2(13)) ex1_p2 (.clk(clk), .reset(reset), .ce(ce), .in(ex1_f1),   .out(ex1_src));
	dsc_lpf #(.S0(4), .S1(6),  .S2(9), .N1(1'b1), .N2(1'b1)) ex2_p1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(ex2_f1));
	dsc_lpf #(.S0(7), .S1(9),  .S2(11), .N2(1'b1)) ex2_p2
		(.clk(clk), .reset(reset), .ce(ce), .in(ex2_f1), .out(ex2_src));
	dsc_lpf #(.S0(4), .S1(6),  .S2(9), .N1(1'b1), .N2(1'b1)) ex3_p1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(ex3_f1));
	dsc_lpf #(.S0(7), .S1(9),  .S2(11), .N2(1'b1)) ex3_p2
		(.clk(clk), .reset(reset), .ce(ce), .in(ex3_f1), .out(ex3_src));

	wire [15:0] env_fire_raw, env_ex1, env_ex2, env_ex3, env_bounce;
	dsc_decay_env #(.D0(13), .D1(16)) fire_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[1]), .level(env_fire_raw), .trigger());
	dsc_decay_env #(.D0(15), .D1(16), .D2(17)) ex1_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[2]), .level(env_ex1), .trigger());
	dsc_decay_env #(.D0(15), .D1(17), .D2(18)) ex2_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[3]), .level(env_ex2), .trigger());
	dsc_decay_env #(.D0(15), .D1(17), .D2(18)) ex3_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[4]), .level(env_ex3), .trigger());
	dsc_decay_env #(.D0(12)) bounce_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[5]), .level(env_bounce), .trigger());
	logic [31:0] env_fire_state;
	wire signed [32:0] env_fire_delta = $signed({1'b0, env_fire_raw, 16'd0})
		- $signed({1'b0, env_fire_state});
	wire signed [32:0] env_fire_next = $signed({1'b0, env_fire_state})
		+ (env_fire_delta >>> 12) + (env_fire_delta >>> 14)
		+ (env_fire_delta >>> 15);
	always_ff @(posedge clk) begin
		if (reset) begin
			env_fire_state <= '0;
		end else if (ce) begin
			env_fire_state <= env_fire_next <= 0 ? 32'd0 : env_fire_next[31:0];
		end
	end
	wire [15:0] env_fire = env_fire_state[31:16];

	// Fireball sums equal tone and noise paths. Eliminator bounce follows the
	// 4:3 tone/noise conductance ratio; Zektor omits its noise resistor.
	wire signed [15:0] tone_70 = osc_70 ? 16'sd24576 : -16'sd24576;
	wire signed [15:0] fire_src = (tone_70 >>> 1) + (noise_raw >>> 1);
	wire signed [15:0] bounce_src = zektor
		? (tone_70 >>> 1) + (tone_70 >>> 4)
		: (tone_70 >>> 1) + (tone_70 >>> 4)
		+ (noise_raw >>> 1) - (noise_raw >>> 4);
	wire signed [15:0] fire_vca_out, fire_voice;
	wire signed [15:0] ex1_voice, ex2_voice, ex3_voice, bounce_voice;
	dsc_vca fire_vca  (.signal(fire_src),   .gain(env_fire),   .out(fire_vca_out));
	assign fire_voice = (fire_vca_out >>> 1) + (fire_vca_out >>> 3)
		+ (fire_vca_out >>> 5);
	dsc_vca ex1_vca   (.signal(ex1_src),    .gain(env_ex1),    .out(ex1_voice));
	dsc_vca ex2_vca   (.signal(ex2_src),    .gain(env_ex2),    .out(ex2_voice));
	dsc_vca ex3_vca   (.signal(ex3_src),    .gain(env_ex3),    .out(ex3_voice));
	dsc_vca bounce_vca(.signal(bounce_src), .gain(env_bounce), .out(bounce_voice));

	// Both torpedoes enable the weighted divider during the VCO's descending
	// 300 ms sweep. The second board's noise path is inaudible in the netlist.
	wire signed [15:0] torp1_voice, torp2_voice;
	sega_elim_torpedo torp1 (
		.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[6]), .out(torp1_voice)
	);
	sega_elim_torpedo torp2 (
		.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[7]), .out(torp2_voice)
	);

	// D0/D1 and D2/D3 set the levels of two cascaded low-pass noise paths.
	wire signed [15:0] thrust_a_p1, thrust_a_p2;
	wire signed [15:0] thrust_b_p1, thrust_b_p2;
	dsc_lpf #(.S0(7), .S1(9), .S2(11), .N2(1'b1)) thrust_a1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(thrust_a_p1));
	dsc_lpf #(.S0(8), .S1(11), .S2(13)) thrust_a2
		(.clk(clk), .reset(reset), .ce(ce), .in(thrust_a_p1), .out(thrust_a_p2));
	dsc_lpf #(.S0(7), .S1(10), .S2(12), .N1(1'b1), .N2(1'b1)) thrust_b1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(thrust_b_p1));
	dsc_lpf #(.S0(8), .S1(12), .S2(14), .N1(1'b1)) thrust_b2
		(.clk(clk), .reset(reset), .ce(ce), .in(thrust_b_p1), .out(thrust_b_p2));
	wire [15:0] target_gain_a = amp_2bit(hi_on[1:0]);
	wire [15:0] target_gain_b = amp_2bit(hi_on[3:2]);
	logic [15:0] thrust_a_gain, thrust_b_gain;
	wire [16:0] diff_a_rise = {1'b0, target_gain_a - thrust_a_gain} >> 8;
	wire [16:0] diff_a_fall = {1'b0, thrust_a_gain - target_gain_a} >> 8;
	wire [16:0] diff_b_rise = {1'b0, target_gain_b - thrust_b_gain} >> 8;
	wire [16:0] diff_b_fall = {1'b0, thrust_b_gain - target_gain_b} >> 8;

	always_ff @(posedge clk) begin
		if (reset) begin
			thrust_a_gain <= 16'd0;
			thrust_b_gain <= 16'd0;
		end else if (ce) begin
			if (thrust_a_gain < target_gain_a)
				thrust_a_gain <= thrust_a_gain + ((diff_a_rise != 0) ? diff_a_rise[15:0] : 16'd1);
			else if (thrust_a_gain > target_gain_a)
				thrust_a_gain <= thrust_a_gain - ((diff_a_fall != 0) ? diff_a_fall[15:0] : 16'd1);

			if (thrust_b_gain < target_gain_b)
				thrust_b_gain <= thrust_b_gain + ((diff_b_rise != 0) ? diff_b_rise[15:0] : 16'd1);
			else if (thrust_b_gain > target_gain_b)
				thrust_b_gain <= thrust_b_gain - ((diff_b_fall != 0) ? diff_b_fall[15:0] : 16'd1);
		end
	end

	wire signed [15:0] thrust_a_level, thrust_b_level;
	dsc_vca thrust_a_vca(.signal(thrust_a_p2), .gain(thrust_a_gain), .out(thrust_a_level));
	dsc_vca thrust_b_vca(.signal(thrust_b_p2), .gain(thrust_b_gain), .out(thrust_b_level));
	wire signed [25:0] thrust_a_mix = zektor
		? (sx16(thrust_a_level) <<< 2) - (sx16(thrust_a_level) >>> 3)
		: sx16(thrust_a_level) + (sx16(thrust_a_level) >>> 2)
			+ (sx16(thrust_a_level) >>> 3);
	wire signed [25:0] thrust_b_mix = (hi_on[3:2] == 2'b11)
		? sx16(thrust_b_level) + (sx16(thrust_b_level) >>> 2)
		: sx16(thrust_b_level) + (sx16(thrust_b_level) >>> 3);
	wire signed [25:0] thrust_sum = thrust_a_mix + thrust_b_mix;
	wire signed [15:0] thrust_voice = thrust_sum > 26'sd32767 ? 16'sh7FFF
		: thrust_sum < -26'sd32768 ? -16'sh8000 : thrust_sum[15:0];

	// C9 and the transistor oscillator modulate the 555's rate and duty cycle.
	wire [15:0] skitter_sweep;
	dsc_decay_env #(.D0(14)) skitter_sweep_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[4]), .level(skitter_sweep), .trigger());
	wire [31:0] skitter_inc_base = zektor ? hz_inc(1400) : hz_inc(600);
	wire [31:0] skitter_sweep_span = zektor ? hz_inc(700) : hz_inc(250);
	wire [31:0] skitter_mod_span = zektor ? hz_inc(400) : hz_inc(200);
	wire [39:0] skitter_sweep_product = skitter_sweep_span * skitter_sweep[15:8];
	wire [39:0] skitter_mod_product = skitter_mod_span * mod_35[15:8];
	wire [31:0] skitter_inc = skitter_inc_base
		+ skitter_sweep_product[39:8] + skitter_mod_product[39:8];
	wire signed [17:0] skitter_mod_duty = $signed({2'b00, mod_35}) - 18'sd32768;
	wire signed [17:0] skitter_duty_ext = 18'sd32768
		- $signed({2'b00, skitter_sweep >> 3})
		+ $signed({2'b00, skitter_sweep >> 5})
		+ (skitter_mod_duty >>> 4);
	wire [15:0] skitter_duty = skitter_duty_ext[15:0];
	wire skitter_pulse;
	dsc_pwm_osc skitter_osc (
		.clk(clk), .reset(reset), .ce(ce), .inc(skitter_inc),
		.duty(skitter_duty), .pulse(skitter_pulse)
	);
	wire signed [15:0] skitter_raw = skitter_pulse
		? (zektor ? 16'sd10240 : 16'sd12000)
		: (zektor ? -16'sd10240 : -16'sd12000);
	wire [15:0] skitter_env;
	dsc_gate_env #(.ATK(5), .REL(7)) skitter_gate
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[4]), .level(skitter_env));
	wire signed [15:0] skitter_voice;
	dsc_vca skitter_vca(.signal(skitter_raw), .gain(skitter_env), .out(skitter_voice));

	// The enemy 555 control pin is driven by the 10.58 and 121.12 Hz clocks.
	wire [31:0] enemy_inc = hz_inc(660)
		+ (osc_10  ? hz_inc(20) : 32'd0)
		+ (osc_121 ? hz_inc(30) : 32'd0);
	wire enemy_pulse;
	dsc_pwm_osc enemy_osc (
		.clk(clk), .reset(reset), .ce(ce), .inc(enemy_inc),
		.duty(16'h828F), .pulse(enemy_pulse)
	);
	wire signed [15:0] enemy_raw = enemy_pulse ? 16'sd13000 : -16'sd13000;
	wire [15:0] enemy_env;
	dsc_gate_env #(.ATK(5), .REL(7)) enemy_gate
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[5]), .level(enemy_env));
	wire signed [15:0] enemy_voice;
	dsc_vca enemy_vca(.signal(enemy_raw), .gain(enemy_env), .out(enemy_voice));

	// D6/D7 select the background VCO target while its control capacitor charges.
	logic [31:0] background_inc, background_target;
	always_comb begin
		case (hi_on[7:6])
			2'd0: background_target = hz_inc(100);
			2'd1: background_target = hz_inc(155);
			2'd2: background_target = hz_inc(230);
			default: background_target = hz_inc(305);
		endcase
	end
	wire signed [32:0] background_delta = $signed({1'b0, background_target})
		- $signed({1'b0, background_inc});
	wire signed [32:0] background_next = $signed({1'b0, background_inc})
		+ (background_delta >>> 14);
	always_ff @(posedge clk) begin
		if (reset || !(|hi_on[7:6]))
			background_inc <= hz_inc(100);
		else if (ce)
			background_inc <= background_next[31:0];
	end
	wire background_sq;
	dsc_osc background_osc
		(.clk(clk), .reset(reset), .ce(ce), .inc(background_inc), .square(background_sq));
	wire [16:0] background_mod_target = (osc_70   ? 17'd16384 : 17'd0)
		+ (osc_121  ? 17'd16384 : 17'd0)
		+ (osc_218a ? 17'd16384 : 17'd0)
		+ (osc_218b ? 17'd16384 : 17'd0)
		+ (osc_10   ? 17'd4096  : 17'd0);
	logic [16:0] background_mod_state;
	wire signed [17:0] background_mod_delta = $signed({1'b0, background_mod_target})
		- $signed({1'b0, background_mod_state});
	wire signed [17:0] background_mod_next = $signed({1'b0, background_mod_state})
		+ (background_mod_delta >>> 4);
	always_ff @(posedge clk) begin
		if (reset)
			background_mod_state <= '0;
		else if (ce)
			background_mod_state <= background_mod_next[16:0];
	end
	wire [15:0] background_mod = background_mod_state[16]
		? 16'hFFFF : background_mod_state[15:0];
	wire signed [15:0] background_raw = background_sq ? 16'sh7FFF : -16'sh7FFF;
	wire signed [15:0] background_am;
	dsc_vca background_ota
		(.signal(background_raw), .gain(background_mod), .out(background_am));
	wire [15:0] background_env;
	dsc_gate_env #(.ATK(5), .REL(7)) background_gate
		(.clk(clk), .reset(reset), .ce(ce), .gate(|hi_on[7:6]), .level(background_env));
	wire signed [15:0] background_voice;
	dsc_vca background_vca
		(.signal(background_am), .gain(background_env), .out(background_voice));

	// Zektor's three AY channels enter the board through equal 1K resistors.
	wire [9:0] ay_sum = {2'd0, ay_a} + {2'd0, ay_b} + {2'd0, ay_c};
	wire signed [15:0] ay_raw = $signed({1'b0, ay_sum, 5'd0});
	wire signed [15:0] ay_ac;
	dsc_hpf #(.S0(9), .S1(13), .S2(17)) ay_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(ay_raw), .out(ay_ac));

	// The event VCAs share one saturating summing amplifier before R8.
	wire signed [25:0] event_fire = (sx16(fire_voice) >>> 1) + (sx16(fire_voice) >>> 4);
	wire signed [25:0] event_ex1 = (sx16(ex1_voice) <<< 6) + (sx16(ex1_voice) <<< 4);
	wire signed [25:0] event_ex2 = (sx16(ex2_voice) <<< 4)
		+ (sx16(ex2_voice) <<< 1) + sx16(ex2_voice) + (sx16(ex2_voice) >>> 1);
	wire signed [25:0] event_ex3 = (sx16(ex3_voice) <<< 3)
		+ (sx16(ex3_voice) <<< 1) + sx16(ex3_voice);
	wire signed [25:0] event_bounce = (sx16(bounce_voice) >>> 2)
		+ (sx16(bounce_voice) >>> 6);
	wire signed [25:0] event_thrust = sx16(thrust_voice) <<< 2;
	wire signed [25:0] event_background = sx16(background_voice) >>> 6;
	wire signed [25:0] event_pair_0 = event_fire + event_ex1;
	wire signed [25:0] event_pair_1 = event_ex2 + event_ex3;
	wire signed [25:0] event_pair_2 = event_bounce + event_thrust;
	wire signed [25:0] event_mix = (event_pair_0 + event_pair_1)
		+ (event_pair_2 + event_background);
	wire signed [15:0] event_bus = event_mix > 26'sd28672 ? 16'sd28672
		: event_mix < -26'sd28672 ? -16'sd28672 : event_mix[15:0];

	// R6/R7 are 220K; R8 is 10K; R9 is 33K on Eliminator and 12K
	// on Zektor; R10 gives the PSG unity gain.
	wire signed [16:0] torpedo_sum = {torp1_voice[15], torp1_voice}
		+ {torp2_voice[15], torp2_voice};
	wire signed [15:0] torpedo_pre = torpedo_sum > 17'sd32767 ? 16'sh7FFF
		: torpedo_sum < -17'sd32768 ? -16'sh8000 : torpedo_sum[15:0];
	wire signed [15:0] torpedo_elim, torpedo_zektor;
	dsc_hpf #(.S0(7), .S1(9), .N1(1'b1)) torpedo_coupling_elim
		(.clk(clk), .reset(reset), .ce(ce), .in(torpedo_pre), .out(torpedo_elim));
	dsc_hpf #(.S0(6), .S1(9)) torpedo_coupling_zektor
		(.clk(clk), .reset(reset), .ce(ce), .in(torpedo_pre), .out(torpedo_zektor));
	wire signed [25:0] torpedo_mix = sx16(zektor ? torpedo_zektor : torpedo_elim);
	wire signed [25:0] quiet_mix = (sx16(skitter_voice) >>> 5)
		+ (sx16(skitter_voice) >>> 6) - (sx16(skitter_voice) >>> 9)
		+ (sx16(enemy_voice) >>> 5) + (sx16(enemy_voice) >>> 6)
		- (sx16(enemy_voice) >>> 9);
	wire signed [25:0] torpedo_resistor = zektor
		? torpedo_mix - (torpedo_mix >>> 3) - (torpedo_mix >>> 5) - (torpedo_mix >>> 7)
		: (torpedo_mix >>> 2) + (torpedo_mix >>> 4) - (torpedo_mix >>> 7);
	wire signed [25:0] torpedo_base = (torpedo_resistor >>> 2) - (torpedo_resistor >>> 4);
	wire signed [25:0] torpedo_weighted = zektor
		? torpedo_base - (torpedo_base >>> 2) - (torpedo_base >>> 5)
		: torpedo_base;
	wire signed [25:0] board_mix = sx16(event_bus) + quiet_mix + torpedo_weighted
		+ (zektor ? sx16(ay_ac) : 26'sd0);
	wire signed [15:0] board_clipped = board_mix > 26'sd32767 ? 16'sh7FFF
		: board_mix < -26'sd32768 ? -16'sh8000 : board_mix[15:0];

	// The output coupling capacitor removes control-voltage and envelope DC.
	dsc_hpf #(.S0(10), .S1(14), .S2(18)) output_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(board_clipped), .out(audio));
endmodule

`default_nettype wire
