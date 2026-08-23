//============================================================================
//  Sega Space Fury sound board
//
//  Written by Videodr0me
//
//  Oscillators, RC poles, divider taps, and final mixing follow Sega drawing
//  800-3059 and MAME's nl_spacfury.cpp netlist.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_fury_shoot (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire               gate,
	output wire signed [15:0] out
);
	logic gate_q, pending, active, restart;
	logic [9:0] sample_count;
	logic [4:0] sweep_step;
	logic [15:0] freq_hz;

	always_comb begin
		case (sweep_step)
			 0: freq_hz = 16'd7600;
			 1: freq_hz = 16'd6500;
			 2: freq_hz = 16'd5500;
			 3: freq_hz = 16'd4600;
			 4: freq_hz = 16'd3900;
			 5: freq_hz = 16'd3400;
			 6: freq_hz = 16'd3000;
			 7: freq_hz = 16'd2700;
			 8: freq_hz = 16'd2450;
			 9: freq_hz = 16'd2250;
			10: freq_hz = 16'd2080;
			11: freq_hz = 16'd1920;
			12: freq_hz = 16'd1780;
			13: freq_hz = 16'd1650;
			14: freq_hz = 16'd1530;
			15: freq_hz = 16'd1420;
			16: freq_hz = 16'd1320;
			17: freq_hz = 16'd1220;
			18: freq_hz = 16'd1120;
			19: freq_hz = 16'd1020;
			20: freq_hz = 16'd920;
			21: freq_hz = 16'd820;
			22: freq_hz = 16'd720;
			default: freq_hz = 16'd620;
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
					if (sample_count == 10'd599) begin
						sample_count <= '0;
						if (sweep_step == 5'd23)
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

	logic [15:0] shoot_env;
	wire [16:0] shoot_env_rise = {1'b0, 16'hFFFF - shoot_env} >> 6;
	wire [15:0] shoot_env_fall = shoot_env >> 7;

	always_ff @(posedge clk) begin
		if (reset) begin
			shoot_env <= 16'd0;
		end else if (ce) begin
			if (active) begin
				if (shoot_env != 16'hFFFF)
					shoot_env <= shoot_env + ((shoot_env_rise != 0) ? shoot_env_rise[15:0] : 16'd1);
			end else if (shoot_env != 16'd0) begin
				shoot_env <= (shoot_env > shoot_env_fall) ? shoot_env - ((shoot_env_fall != 0) ? shoot_env_fall : 16'd1) : 16'd0;
			end
		end
	end

	wire signed [15:0] divider_out;
	dsc_swept_divider divider (
		.clk(clk), .reset(reset), .ce(ce), .restart(restart),
		.freq_hz(freq_hz), .out(divider_out)
	);

	dsc_vca shoot_vca (
		.signal(divider_out),
		.gain(shoot_env),
		.out(out)
	);
endmodule

// Star Spin and Partial Warship share the active network feeding board R20.
module sega_fury_spin_warship #(
	parameter int CE_HZ = 48_000
) (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire               spin_gate,
	input  wire               warship_gate,
	input  wire signed [15:0] osc_bank,
	input  wire signed [15:0] noise,
	output wire signed [15:0] out
);
	function automatic [31:0] mhz_inc(input integer mhz);
		logic [63:0] scaled;
		begin
			scaled = (64'd4294967296 * 64'(mhz)) / (64'(CE_HZ) * 64'd1000);
			mhz_inc = scaled[31:0];
		end
	endfunction

	// The shared filter control rests near 2.5 Hz. Star Spin charges it toward
	// 9.5 Hz, reproducing the accelerating sweep of the board oscillator.
	logic [31:0] spin_charge;
	wire signed [32:0] spin_charge_delta = $signed({1'b0, 32'hFFFF_FFFF})
		- $signed({1'b0, spin_charge});
	wire signed [32:0] spin_charge_step = (spin_charge_delta >>> 16)
		- (spin_charge_delta >>> 20);
	always_ff @(posedge clk) begin
		if (reset) begin
			spin_charge <= '0;
		end else if (ce) begin
			if (spin_gate)
				spin_charge <= spin_charge + spin_charge_step[31:0];
			else
				spin_charge <= spin_charge - (spin_charge >> 12);
		end
	end

	wire [31:0] spin_inc_span = mhz_inc(7000);
	wire [39:0] spin_inc_product = spin_inc_span * spin_charge[31:24];
	wire [31:0] spin_inc = mhz_inc(2500) + spin_inc_product[39:8];
	wire [15:0] spin_lfo;
	dsc_triangle spin_control
		(.clk(clk), .reset(reset), .ce(ce), .inc(spin_inc), .wave(spin_lfo));
	wire [5:0] spin_pos = spin_lfo[15:10];
	wire [6:0] spin_pos_ext = {1'b0, spin_pos};
	// The 9-bit coefficient spans about 478 Hz through 1674 Hz.
	wire [6:0] spin_coeff = 7'd32 + spin_pos_ext
		+ ((spin_pos_ext + 7'd1) >> 2) + ((spin_pos_ext + 7'd1) >> 6);

	// R63 feeds the three O1/O2/O3 oscillators at about one fifth of the
	// R64 noise current. Both sources then pass through the same U7/U8/U12
	// state-variable network.
	wire [15:0] env_warship, env_spin;
	dsc_gate_env #(.ATK(6), .REL(8)) warship_env_inst
		(.clk(clk), .reset(reset), .ce(ce), .gate(warship_gate), .level(env_warship));
	dsc_gate_env #(.ATK(6), .REL(8)) spin_env_inst
		(.clk(clk), .reset(reset), .ce(ce), .gate(spin_gate), .level(env_spin));

	wire signed [15:0] warship_raw = osc_bank <<< 4;
	wire signed [15:0] warship_drive, noise_drive;
	dsc_vca warship_vca(.signal(warship_raw), .gain(env_warship), .out(warship_drive));
	dsc_vca noise_vca(.signal(noise), .gain(env_spin), .out(noise_drive));

	wire signed [16:0] filter_in_ext = {noise_drive[15], noise_drive}
		+ {warship_drive[15], warship_drive};
	wire signed [15:0] filter_in = filter_in_ext > 17'sd32767 ? 16'sh7FFF
		: filter_in_ext < -17'sd32768 ? -16'sh8000 : filter_in_ext[15:0];
	logic signed [39:0] spin_low, spin_band, spin_band_next_q;
	logic signed [47:0] spin_high_product_q, spin_band_product_q;
	logic        [6:0] spin_coeff_q;
	logic        [1:0] spin_filter_phase;
	wire signed [39:0] spin_in = {{8{filter_in[15]}}, filter_in, 16'd0};
	wire signed [39:0] spin_high = spin_in - spin_low - (spin_band >>> 2);
	wire signed [47:0] spin_high_shifted = spin_high_product_q >>> 9;
	wire signed [39:0] spin_high_step = spin_high_shifted[39:0];
	wire signed [39:0] spin_band_next = spin_band + spin_high_step;
	wire signed [47:0] spin_band_shifted = spin_band_product_q >>> 9;
	wire signed [39:0] spin_band_step = spin_band_shifted[39:0];

	always_ff @(posedge clk) begin
		if (reset) begin
			spin_low             <= '0;
			spin_band            <= '0;
			spin_band_next_q     <= '0;
			spin_high_product_q  <= '0;
			spin_band_product_q  <= '0;
			spin_coeff_q         <= '0;
			spin_filter_phase    <= '0;
		end else begin
			case (spin_filter_phase)
				2'd0: if (ce) begin
					spin_coeff_q        <= spin_coeff;
					spin_high_product_q <= spin_high * $signed({1'b0, spin_coeff});
					spin_filter_phase   <= 2'd1;
				end
				2'd1: begin
					spin_band_next_q    <= spin_band_next;
					spin_band_product_q <= spin_band_next * $signed({1'b0, spin_coeff_q});
					spin_filter_phase   <= 2'd2;
				end
				default: begin
					spin_low          <= spin_low + spin_band_step;
					spin_band         <= spin_band_next_q;
					spin_filter_phase <= 2'd0;
				end
			endcase
		end
	end

	// U8.1 supplies Star Spin's low-frequency body. Partial Warship retains
	// the band state needed for its measured harmonic balance.
	wire signed [23:0] spin_raw = spin_gate
		? spin_low[39:16] : spin_band[39:16];
	wire signed [24:0] spin_ext = {spin_raw[23], spin_raw};
	wire signed [24:0] spin_normalized = spin_ext + (spin_ext >>> 3);
	wire signed [24:0] spin_scaled = spin_normalized >>> 2;
	wire signed [15:0] shared_voice = spin_scaled > 25'sd32767 ? 16'sh7FFF
		: spin_scaled < -25'sd32768 ? -16'sh8000 : spin_scaled[15:0];
	dsc_hpf #(.S0(8)) shared_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(shared_voice), .out(out));
endmodule

// Crafts Joining and Docking Bang share the O4/O5/O6 oscillator bank.
module sega_fury_join_dock (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        joining_gate,
	input  wire        docking_gate,
	input  wire        osc_a,
	input  wire        osc_b,
	input  wire        osc_c,
	output wire signed [15:0] joining,
	output wire signed [15:0] docking
);
	// Q9/Q10 steer Q13's envelope current. The piecewise curve approximates
	// tanh(Vbe/2VT), with the input represented in Q8.
	function automatic signed [15:0] diff_pair_transfer(input signed [23:0] value);
		logic [23:0] magnitude;
		logic [31:0] shaped;
		begin
			magnitude = value[23] ? (~value + 1'b1) : value;
			if (magnitude < 24'd16384)
				shaped = (magnitude << 6) + (magnitude << 4)
					+ (magnitude << 2) + (magnitude << 1);
			else if (magnitude < 24'd32768)
				shaped = 32'd1409024 + ((magnitude - 24'd16384) << 5)
					+ ((magnitude - 24'd16384) << 4) + ((magnitude - 24'd16384) << 3);
			else if (magnitude < 24'd65536)
				shaped = 32'd2326528 + ((magnitude - 24'd32768) << 4)
					+ ((magnitude - 24'd32768) << 1) + (magnitude - 24'd32768);
			else if (magnitude < 24'd106496)
				shaped = 32'd2949120 + ((magnitude - 24'd65536) << 1)
					+ (magnitude - 24'd65536);
			else
				shaped = 32'd3072000;
			diff_pair_transfer = value[23] ? -$signed(shaped[23:8]) : $signed(shaped[23:8]);
		end
	endfunction

	localparam logic signed [15:0] OSC_LEVEL  = 16'sd16000;
	wire signed [15:0] osc_wa = osc_a ? OSC_LEVEL : -OSC_LEVEL;
	wire signed [15:0] osc_wb = osc_b ? OSC_LEVEL : -OSC_LEVEL;
	wire signed [15:0] osc_wc = osc_c ? OSC_LEVEL : -OSC_LEVEL;
	wire signed [17:0] osc_sum = {{2{osc_wa[15]}}, osc_wa}
		+ {{2{osc_wb[15]}}, osc_wb} + {{2{osc_wc[15]}}, osc_wc};
	wire signed [16:0] join_half = osc_sum[17:1];
	wire signed [16:0] join_shaped = join_half[16] ? join_half >>> 1 : join_half;
	wire signed [16:0] join_ext = join_shaped + (join_shaped >>> 2);
	wire signed [15:0] join_src = join_ext[15:0];
	wire signed [15:0] join_band;
	dsc_lpf #(.S0(5)) joining_bandwidth
		(.clk(clk), .reset(reset), .ce(ce), .in(join_src), .out(join_band));
	wire [15:0] join_env;
	dsc_diff_env #(.FAST(10), .SLOW(15), .SLOW1(16)) joining_envelope
		(.clk(clk), .reset(reset), .ce(ce), .gate(joining_gate), .level(join_env));
	dsc_vca joining_vca(.signal(join_band), .gain(join_env), .out(joining));

	// C59/C60 and U18B form a resonant differentiator near 390 Hz. Q9/Q10
	// limit its output under Q13's envelope.
	wire signed [17:0] dock_src_ext = osc_sum >>> 1;
	wire signed [15:0] dock_src = dock_src_ext[15:0];
	wire signed [15:0] dock_input, dock_band;
	dsc_hpf #(.S0(4)) docking_input_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(dock_src), .out(dock_input));
	dsc_resonator #(
		.F0(4), .F1(7), .F1_NEG(1'b1), .F2(9), .F2_NEG(1'b1), .F3(10), .F3_NEG(1'b1),
		.D0(3), .D1(5), .D2(6)
	) docking_filter (
		.clk(clk), .reset(reset), .ce(ce), .in(dock_input >>> 3), .out(dock_band)
	);
	// R111/R110 attenuate U18B by 100/10100 before Q10.
	wire signed [23:0] dock_band_ext = {{8{dock_band[15]}}, dock_band};
	wire signed [23:0] dock_pair_product = (dock_band_ext <<< 6)
		+ (dock_band_ext <<< 4) + dock_band_ext;
	wire signed [23:0] dock_pair_q8 = dock_pair_product >>> 5;
	wire signed [15:0] dock_drive = diff_pair_transfer(dock_pair_q8);
	wire [15:0] dock_env_raw;
	dsc_diff_env #(.FAST(10), .SLOW(15), .SLOW1(16)) docking_envelope
		(.clk(clk), .reset(reset), .ce(ce), .gate(docking_gate), .level(dock_env_raw));
	wire [15:0] dock_env_delta = dock_env_raw > 16'h0800
		? dock_env_raw - 16'h0800 : 16'd0;
	wire [16:0] dock_env_ext = {1'b0, dock_env_delta}
		+ ({1'b0, dock_env_delta} >> 5);
	wire [15:0] dock_env = dock_env_ext[16] ? 16'hFFFF : dock_env_ext[15:0];
	dsc_vca docking_vca(.signal(dock_drive), .gain(dock_env), .out(docking));
endmodule

module sega_spacfury_sound #(
	parameter int CE_HZ = 48_000
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire  [7:0] lo_on,
	input  wire  [7:0] hi_on,
	input  wire        noise,
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

	function automatic signed [23:0] sx16(input signed [15:0] value);
		sx16 = {{8{value[15]}}, value};
	endfunction

	wire signed [15:0] noise_raw = noise ? 16'sd24576 : -16'sd24576;

	// The board uses three slightly detuned oscillators in each low-frequency bank.
	wire move_a, move_b, move_c, join_a, join_b, join_c;
	dsc_osc move_1(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(105700)), .square(move_a));
	dsc_osc move_2
		(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(105800)), .square(move_b));
	dsc_osc move_3
		(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(105900)), .square(move_c));
	dsc_osc join_1(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(102050)), .square(join_a));
	dsc_osc #(.INIT(32'h5555_5555)) join_2
		(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(69580)), .square(join_b));
	dsc_osc #(.INIT(32'hAAAA_AAAB)) join_3
		(.clk(clk), .reset(reset), .ce(ce), .inc(mhz_inc(102150)), .square(join_c));

	wire signed [15:0] move_wa = move_a ? 16'sd22000 : -16'sd22000;
	wire signed [15:0] move_wb = move_b ? 16'sd22000 : -16'sd22000;
	wire signed [15:0] move_wc = move_c ? 16'sd22000 : -16'sd22000;
	wire signed [15:0] move_src = (move_wa >>> 6) + (move_wb >>> 6) + (move_wc >>> 6);

	// The active sections retain the slow beat and emphasize its upper harmonics.
	logic signed [15:0] move_src_q;
	always_ff @(posedge clk) begin
		if (reset) move_src_q <= '0;
		else if (ce) move_src_q <= move_src;
	end
	wire signed [15:0] move_edge = move_src - move_src_q;
	wire signed [15:0] move_main_ac, move_main, move_air_ac, move_air_1, move_air;
	dsc_hpf #(.S0(6), .S1(7)) moving_main_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(move_src), .out(move_main_ac));
	dsc_lpf #(.S0(4), .S1(6)) moving_main_bandwidth
		(.clk(clk), .reset(reset), .ce(ce), .in(move_main_ac), .out(move_main));
	dsc_hpf #(.S0(3)) moving_air_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(move_edge), .out(move_air_ac));
	dsc_lpf #(.S0(2), .S1(5)) moving_air_bandwidth
		(.clk(clk), .reset(reset), .ce(ce), .in(move_air_ac), .out(move_air_1));
	dsc_lpf #(.S0(2)) moving_air_bandwidth_2
		(.clk(clk), .reset(reset), .ce(ce), .in(move_air_1), .out(move_air));
	wire signed [15:0] moving_band;
	dsc_resonator #(.F0(2), .F1(6), .F1_NEG(1'b1), .D0(1)) moving_resonator
		(.clk(clk), .reset(reset), .ce(ce), .in(move_src), .out(moving_band));
	wire signed [15:0] moving_body = (move_main >>> 1) + (move_air <<< 2);
	wire signed [15:0] moving_src = moving_body + (moving_body >>> 2)
		+ (moving_band >>> 3);
	wire [15:0] env_moving;
	dsc_gate_env #(.ATK(6), .REL(8)) moving_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[1]), .level(env_moving));
	wire signed [15:0] moving_voice;
	dsc_vca moving_vca(.signal(moving_src), .gain(env_moving), .out(moving_voice));

	// The scale oscillator charges toward 400 Hz while the test input is held.
	logic [31:0] scale_control;
	wire [31:0] scale_delta = 32'hFFFF_FFFF - scale_control;
	always_ff @(posedge clk) begin
		if (reset || !lo_on[0]) begin
			scale_control <= '0;
		end else if (ce) begin
			scale_control <= scale_control + (scale_delta >> 13) - (scale_delta >> 15);
		end
	end
	wire [31:0] scale_inc_span = hz_inc(400) - hz_inc(240);
	wire [39:0] scale_inc_product = scale_inc_span * scale_control[31:24];
	wire [31:0] scale_inc = hz_inc(240) + scale_inc_product[39:8];
	wire [15:0] scale_duty = 16'h9999 - (scale_control[31:16] >> 3)
		- (scale_control[31:16] >> 4);
	wire scale_pulse;
	dsc_pwm_osc scale_osc (
		.clk(clk), .reset(reset), .ce(ce), .inc(scale_inc),
		.duty(scale_duty), .pulse(scale_pulse)
	);
	wire signed [15:0] scale_src = scale_pulse ? 16'sd10400 : -16'sd10400;
	wire [15:0] env_scale;
	dsc_gate_env #(.ATK(6), .REL(8)) scale_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[0]), .level(env_scale));
	wire signed [15:0] scale_voice;
	dsc_vca scale_vca(.signal(scale_src), .gain(env_scale), .out(scale_voice));

	wire signed [15:0] star_warship;
	sega_fury_spin_warship #(.CE_HZ(CE_HZ)) spin_warship (
		.clk(clk), .reset(reset), .ce(ce), .spin_gate(lo_on[6]),
		.warship_gate(lo_on[7]), .osc_bank(move_src), .noise(noise_raw),
		.out(star_warship)
	);

	// THRUST uses the board's roughly 220 Hz and 50 Hz noise poles.
	wire signed [15:0] thrust_low_1, thrust_low_2, thrust_low_3, thrust_band;
	dsc_lpf #(.S0(6), .S1(7), .S2(8)) thrust_lowpass
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(thrust_low_1));
	dsc_lpf #(.S0(6), .S1(7), .S2(8)) thrust_lowpass_2
		(.clk(clk), .reset(reset), .ce(ce), .in(thrust_low_1), .out(thrust_low_2));
	dsc_lpf #(.S0(6), .S1(7), .S2(8)) thrust_lowpass_3
		(.clk(clk), .reset(reset), .ce(ce), .in(thrust_low_2), .out(thrust_low_3));
	dsc_hpf #(.S0(9), .S1(11), .S2(13)) thrust_highpass
		(.clk(clk), .reset(reset), .ce(ce), .in(thrust_low_3), .out(thrust_band));
	wire signed [15:0] thrust_src = (thrust_band >>> 1) + (thrust_band >>> 2);
	wire [15:0] env_thrust;
	dsc_gate_env #(.ATK(7), .REL(10)) thrust_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(lo_on[2]), .level(env_thrust));
	wire signed [15:0] thrust_voice;
	dsc_vca thrust_vca(.signal(thrust_src), .gain(env_thrust), .out(thrust_voice));

	wire signed [15:0] joining_voice, docking_voice;
	sega_fury_join_dock join_dock (
		.clk(clk), .reset(reset), .ce(ce), .joining_gate(hi_on[0]),
		.docking_gate(hi_on[5]), .osc_a(join_a), .osc_b(join_b), .osc_c(join_c),
		.joining(joining_voice), .docking(docking_voice)
	);

	// Fireball has a quick charge and a long release around filtered noise.
	wire signed [15:0] fire_fast, fire_low_1, fire_low_2, fire_filtered, fire_src;
	dsc_lpf #(.S0(1), .S1(3), .S2(5), .N1(1'b1), .N2(1'b1)) fire_p1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(fire_fast));
	dsc_lpf #(.S0(4), .S1(9), .N1(1'b1)) fire_p2
		(.clk(clk), .reset(reset), .ce(ce), .in(fire_fast), .out(fire_low_1));
	dsc_lpf #(.S0(4), .S1(9), .N1(1'b1)) fire_p3
		(.clk(clk), .reset(reset), .ce(ce), .in(fire_low_1), .out(fire_low_2));
	dsc_hpf #(.S0(10)) fire_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(fire_low_2), .out(fire_filtered));
	assign fire_src = (fire_filtered >>> 1) + (fire_filtered >>> 2)
		+ (fire_filtered >>> 4);
	wire [15:0] env_fire;
	dsc_diff_env #(.FAST(13), .SLOW(14)) fire_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[2]), .level(env_fire));
	wire signed [15:0] fire_voice;
	dsc_vca fire_vca(.signal(fire_src), .gain(env_fire), .out(fire_voice));

	// D3 adds a wider AC-coupled band; D4 retains the lower filtered path.
	wire signed [15:0] explosion_fast, explosion_src;
	dsc_lpf #(.S0(5), .S1(6)) explosion_p1
		(.clk(clk), .reset(reset), .ce(ce), .in(noise_raw), .out(explosion_fast));
	dsc_lpf #(.S0(7), .S1(9)) explosion_p2
		(.clk(clk), .reset(reset), .ce(ce), .in(explosion_fast), .out(explosion_src));
	wire signed [15:0] explosion_small_wide;
	dsc_lpf #(.S0(6), .S1(9), .N1(1'b1)) explosion_small_p2
		(.clk(clk), .reset(reset), .ce(ce), .in(explosion_fast), .out(explosion_small_wide));
	wire [15:0] env_small, env_large;
	dsc_diff_env #(.FAST(10), .SLOW(15), .SLOW1(16)) small_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[3]), .level(env_small));
	dsc_diff_env #(.FAST(10), .SLOW(16)) large_env
		(.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[4]), .level(env_large));
	wire [16:0] env_small_ext = {1'b0, env_small} - ({1'b0, env_small} >> 4);
	wire [15:0] env_small_gain = env_small_ext[16] ? 16'hFFFF : env_small_ext[15:0];
	wire signed [16:0] explosion_air_ext = {explosion_small_wide[15], explosion_small_wide}
		- {explosion_src[15], explosion_src};
	wire signed [15:0] explosion_air_src = explosion_air_ext > 17'sd32767 ? 16'sh7FFF
		: explosion_air_ext < -17'sd32768 ? -16'sh8000 : explosion_air_ext[15:0];
	wire signed [16:0] explosion_small_src_ext = $signed({explosion_src[15], explosion_src})
		+ $signed({explosion_air_src[15], explosion_air_src});
	wire signed [15:0] explosion_small_src = explosion_small_src_ext > 17'sd32767 ? 16'sh7FFF
		: explosion_small_src_ext < -17'sd32768 ? -16'sh8000 : explosion_small_src_ext[15:0];
	wire signed [15:0] explosion_small_high, explosion_small_low_1;
	wire signed [15:0] explosion_small_band, explosion_small_drive;
	dsc_hpf #(.S0(6)) explosion_small_highpass
		(.clk(clk), .reset(reset), .ce(ce), .in(explosion_small_src), .out(explosion_small_high));
	dsc_lpf #(.S0(4)) explosion_small_lowpass_1
		(.clk(clk), .reset(reset), .ce(ce), .in(explosion_small_high), .out(explosion_small_low_1));
	dsc_lpf #(.S0(5)) explosion_small_lowpass_2
		(.clk(clk), .reset(reset), .ce(ce), .in(explosion_small_low_1), .out(explosion_small_band));
	wire signed [16:0] explosion_small_drive_ext = {explosion_small_band[15], explosion_small_band} <<< 1;
	assign explosion_small_drive = explosion_small_drive_ext > 17'sd32767 ? 16'sh7FFF
		: explosion_small_drive_ext < -17'sd32768 ? -16'sh8000 : explosion_small_drive_ext[15:0];
	wire signed [15:0] explosion_small, explosion_large;
	dsc_vca explosion_small_vca
		(.signal(explosion_small_drive), .gain(env_small_gain), .out(explosion_small));
	dsc_vca explosion_large_vca
		(.signal(explosion_src), .gain(env_large), .out(explosion_large));

	// SHOOT clocks the board's weighted CD4024 during a descending 300 ms sweep.
	wire signed [15:0] shoot_voice;
	sega_fury_shoot shoot (
		.clk(clk), .reset(reset), .ce(ce), .gate(hi_on[1]), .out(shoot_voice)
	);

	// Source ordering follows R19-R27; shifts also retain upstream board gain.
	wire signed [23:0] explosion_mix = sx16(explosion_small)
		+ (sx16(explosion_large) <<< 1) + (sx16(explosion_large) >>> 2);
	wire signed [23:0] board_mix = (explosion_mix <<< 1) + explosion_mix
		+ (sx16(thrust_voice) <<< 3) + (sx16(thrust_voice) <<< 1)
		+ sx16(thrust_voice) + (sx16(thrust_voice) >>> 2)
		+ (sx16(fire_voice) <<< 4) + (sx16(fire_voice) <<< 3)
		+ (sx16(star_warship) >>> 1) - (sx16(star_warship) >>> 5)
		- (sx16(star_warship) >>> 6)
		+ (sx16(joining_voice) >>> 1)
		+ (sx16(docking_voice) <<< 3) - sx16(docking_voice)
		+ (sx16(shoot_voice) >>> 3)
		+ (sx16(moving_voice) >>> 1) + (sx16(moving_voice) >>> 3)
		+ (sx16(moving_voice) >>> 4)
		+ (sx16(scale_voice) >>> 4);
	wire signed [23:0] board_scaled = board_mix >>> 1;
	wire signed [15:0] board_clipped = board_scaled > 24'sd32767 ? 16'sh7FFF
		: board_scaled < -24'sd32768 ? -16'sh8000 : board_scaled[15:0];

	dsc_hpf #(.S0(10), .S1(14), .S2(18)) output_coupling
		(.clk(clk), .reset(reset), .ce(ce), .in(board_clipped), .out(audio));
endmodule

`default_nettype wire
