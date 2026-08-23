//============================================================================
//  Sega G-80 discrete-audio building blocks
//
//  Written by Videodr0me
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module dsc_noise (
	input  wire clk,
	input  wire reset,
	input  wire ce,
	output wire out
);
	logic [16:0] shift;

	always_ff @(posedge clk) begin
		if (reset)   shift <= 17'h15555;
		else if (ce) shift <= {shift[15:0], shift[13] ^ shift[16]};
	end

	assign out = shift[16];
endmodule

module dsc_osc #(
	parameter logic [31:0] INIT = 32'd0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire [31:0] inc,
	output wire        square
);
	logic [31:0] phase;

	always_ff @(posedge clk) begin
		if (reset)   phase <= INIT;
		else if (ce) phase <= phase + inc;
	end

	assign square = phase[31];
endmodule

module dsc_pwm_osc #(
	parameter logic [31:0] INIT = 32'd0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire [31:0] inc,
	input  wire [15:0] duty,
	output wire        pulse
);
	logic [31:0] phase;

	always_ff @(posedge clk) begin
		if (reset)   phase <= INIT;
		else if (ce) phase <= phase + inc;
	end

	assign pulse = phase[31:16] < duty;
endmodule

module dsc_triangle #(
	parameter logic [31:0] INIT = 32'd0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire [31:0] inc,
	output wire [15:0] wave
);
	logic [31:0] phase;

	always_ff @(posedge clk) begin
		if (reset)   phase <= INIT;
		else if (ce) phase <= phase + inc;
	end

	assign wave = phase[31] ? ~phase[30:15] : phase[30:15];
endmodule

// One RC pole. K is expressed as up to three signed powers of two:
// K = 2^-S0 + (-1)^N1 2^-S1 + (-1)^N2 2^-S2.
module dsc_lpf #(
	parameter int S0 = 6,
	parameter int S1 = 0,
	parameter int S2 = 0,
	parameter bit N1 = 1'b0,
	parameter bit N2 = 1'b0
) (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire signed [15:0] in,
	output wire signed [15:0] out
);
	logic signed [32:0] state;
	wire signed [32:0] x = {in[15], in, 16'd0};
	wire signed [32:0] delta = x - state;
	wire signed [32:0] term_1 = (S1 != 0) ? (delta >>> S1) : 33'sd0;
	wire signed [32:0] term_2 = (S2 != 0) ? (delta >>> S2) : 33'sd0;
	wire signed [32:0] step = (delta >>> S0)
	                                + (N1 ? -term_1 : term_1)
	                                + (N2 ? -term_2 : term_2);

	always_ff @(posedge clk) begin
		if (reset)   state <= '0;
		else if (ce) state <= state + step;
	end

	assign out = state[31:16];
endmodule

module dsc_hpf #(
	parameter int S0 = 11,
	parameter int S1 = 14,
	parameter int S2 = 17,
	parameter bit N1 = 1'b0,
	parameter bit N2 = 1'b0
) (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire signed [15:0] in,
	output wire signed [15:0] out
);
	wire signed [15:0] low;
	wire signed [16:0] high = {in[15], in} - {low[15], low};

	dsc_lpf #(.S0(S0), .S1(S1), .S2(S2), .N1(N1), .N2(N2)) dc (
		.clk(clk), .reset(reset), .ce(ce), .in(in), .out(low)
	);

	assign out = (high >  17'sd32767) ?  16'sh7FFF :
	             (high < -17'sd32768) ? -16'sh8000 : high[15:0];
endmodule

// Two-integrator resonator with shift-only frequency and damping coefficients.
module dsc_resonator #(
	parameter int F0 = 5,
	parameter int F1 = 6,
	parameter bit F1_NEG = 1'b0,
	parameter int F2 = 0,
	parameter bit F2_NEG = 1'b0,
	parameter int F3 = 0,
	parameter bit F3_NEG = 1'b0,
	parameter int D0 = 2,
	parameter int D1 = 0,
	parameter int D2 = 0
) (
	input  wire               clk,
	input  wire               reset,
	input  wire               ce,
	input  wire signed [15:0] in,
	output wire signed [15:0] out
);
	logic signed [39:0] low, band;
	wire signed [39:0] x = {{8{in[15]}}, in, 16'd0};
	wire signed [39:0] damping = (band >>> D0)
		+ ((D1 != 0) ? band >>> D1 : 40'sd0)
		+ ((D2 != 0) ? band >>> D2 : 40'sd0);
	wire signed [39:0] high = x - low - damping;
	wire signed [39:0] high_term_1 = high >>> F1;
	wire signed [39:0] high_term_2 = (F2 != 0) ? high >>> F2 : 40'sd0;
	wire signed [39:0] high_term_3 = (F3 != 0) ? high >>> F3 : 40'sd0;
	wire signed [39:0] band_term_1 = band >>> F1;
	wire signed [39:0] band_term_2 = (F2 != 0) ? band >>> F2 : 40'sd0;
	wire signed [39:0] band_term_3 = (F3 != 0) ? band >>> F3 : 40'sd0;
	wire signed [39:0] band_next = band + (high >>> F0)
		+ (F1_NEG ? -high_term_1 : high_term_1)
		+ (F2_NEG ? -high_term_2 : high_term_2)
		+ (F3_NEG ? -high_term_3 : high_term_3);
	wire signed [39:0] low_next = low + (band >>> F0)
		+ (F1_NEG ? -band_term_1 : band_term_1)
		+ (F2_NEG ? -band_term_2 : band_term_2)
		+ (F3_NEG ? -band_term_3 : band_term_3);
	wire signed [39:0] sample = band >>> 16;

	always_ff @(posedge clk) begin
		if (reset) begin
			low  <= '0;
			band <= '0;
		end else if (ce) begin
			low  <= low_next;
			band <= band_next;
		end
	end

	assign out = (sample >  40'sd32767) ?  16'sh7FFF :
	             (sample < -40'sd32768) ? -16'sh8000 : sample[15:0];
endmodule

// Edge-triggered decay envelope. A rising gate starts or retriggers it.
module dsc_one_shot #(
	parameter int D0 = 12,
	parameter int D1 = 0,
	parameter int D2 = 0,
	parameter bit N1 = 1'b0,
	parameter bit N2 = 1'b0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        gate,
	output wire [15:0] level,
	output logic       trigger
);
	logic gate_q, pending;
	logic [15:0] env;
	wire [15:0] term_1 = (D1 != 0) ? (env >> D1) : 16'd0;
	wire [15:0] term_2 = (D2 != 0) ? (env >> D2) : 16'd0;
	wire signed [17:0] decay_s = $signed({2'b00, env >> D0})
	                                 + (N1 ? -$signed({2'b00, term_1}) : $signed({2'b00, term_1}))
	                                 + (N2 ? -$signed({2'b00, term_2}) : $signed({2'b00, term_2}));
	wire [15:0] decay = (decay_s <= 0) ? 16'd1 : decay_s[15:0];

	always_ff @(posedge clk) begin
		if (reset) begin
			gate_q  <= 1'b0;
			pending <= 1'b0;
			env     <= 16'd0;
			trigger <= 1'b0;
		end else begin
			gate_q  <= gate;
			trigger <= 1'b0;
			if (gate && !gate_q) pending <= 1'b1;
			if (ce) begin
				if (pending || (gate && !gate_q)) begin
					env     <= 16'hFFFF;
					pending <= 1'b0;
					trigger <= 1'b1;
				end else if (env != 0) begin
					env <= (env > decay) ? env - decay : 16'd0;
				end
			end
		end
	end

	assign level = env;
endmodule

// Triggered exponential decay with fractional state and smooth diode-charging attack.
module dsc_decay_env #(
	parameter int ATK = 6,
	parameter int D0 = 12,
	parameter int D1 = 0,
	parameter int D2 = 0,
	parameter bit N1 = 1'b0,
	parameter bit N2 = 1'b0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        gate,
	output wire [15:0] level,
	output logic       trigger
);
	logic gate_q, pending, charging;
	logic [31:0] env;
	wire [31:0] term_1 = (D1 != 0) ? (env >> D1) : 32'd0;
	wire [31:0] term_2 = (D2 != 0) ? (env >> D2) : 32'd0;
	wire signed [33:0] decay_s = $signed({2'b00, env >> D0})
		+ (N1 ? -$signed({2'b00, term_1}) : $signed({2'b00, term_1}))
		+ (N2 ? -$signed({2'b00, term_2}) : $signed({2'b00, term_2}));
	wire [31:0] decay = (decay_s <= 0) ? 32'd1 : decay_s[31:0];
	wire [32:0] rise_diff = {1'b0, 32'hFFFF_FFFF} - {1'b0, env};
	wire [31:0] rise = (ATK != 0) ? (rise_diff[31:0] >> ATK) : 32'd0;

	always_ff @(posedge clk) begin
		if (reset) begin
			gate_q   <= 1'b0;
			pending  <= 1'b0;
			charging <= 1'b0;
			env      <= 32'd0;
			trigger  <= 1'b0;
		end else begin
			gate_q  <= gate;
			trigger <= 1'b0;
			if (gate && !gate_q) pending <= 1'b1;
			if (ce) begin
				if (pending || (gate && !gate_q)) begin
					pending  <= 1'b0;
					charging <= 1'b1;
					trigger  <= 1'b1;
					if (ATK == 0) begin
						env      <= 32'hFFFF_FFFF;
						charging <= 1'b0;
					end else begin
						env <= env + ((rise != 0) ? rise : 32'd1);
					end
				end else if (charging) begin
					if (env >= 32'hFFF0_0000) begin
						env      <= 32'hFFFF_FFFF;
						charging <= 1'b0;
					end else begin
						env <= env + ((rise != 0) ? rise : 32'd1);
					end
				end else if (env != 0) begin
					env <= (env > decay) ? env - decay : 32'd0;
				end
			end
		end
	end

	assign level = env[31:16];
endmodule

// A triggered RC pulse formed by subtracting a fast decay from a slow decay.
module dsc_diff_env #(
	parameter int FAST = 12,
	parameter int SLOW = 15,
	parameter int SLOW1 = 0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        gate,
	output wire [15:0] level
);
	logic gate_q, pending;
	logic [31:0] fast, slow;
	wire [31:0] fast_decay = fast >> FAST;
	wire [31:0] slow_decay = (slow >> SLOW)
		+ ((SLOW1 != 0) ? (slow >> SLOW1) : 32'd0);
	wire [31:0] difference = slow > fast ? slow - fast : 32'd0;

	always_ff @(posedge clk) begin
		if (reset) begin
			gate_q  <= 1'b0;
			pending <= 1'b0;
			fast    <= 32'd0;
			slow    <= 32'd0;
		end else begin
			gate_q <= gate;
			if (gate && !gate_q) pending <= 1'b1;
			if (ce) begin
				if (pending || (gate && !gate_q)) begin
					pending <= 1'b0;
					fast    <= 32'hFFFF_FFFF;
					slow    <= 32'hFFFF_FFFF;
				end else begin
					if (fast != 0) fast <= fast - ((fast_decay != 0) ? fast_decay : 32'd1);
					if (slow != 0) slow <= slow - ((slow_decay != 0) ? slow_decay : 32'd1);
				end
			end
		end
	end

	assign level = difference[31:16];
endmodule

module dsc_gate_env #(
	parameter int ATK = 8,
	parameter int REL = 10
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        gate,
	output wire [15:0] level
);
	logic [15:0] env;
	wire [16:0] rise = {1'b0, 16'hFFFF - env} >> ATK;
	wire [15:0] fall = env >> REL;

	always_ff @(posedge clk) begin
		if (reset) begin
			env <= 16'd0;
		end else if (ce) begin
			if (gate && env != 16'hFFFF)
				env <= env + ((rise != 0) ? rise[15:0] : 16'd1);
			else if (!gate && env != 0)
				env <= (env > fall) ? env - ((fall != 0) ? fall : 16'd1) : 16'd0;
		end
	end

	assign level = env;
endmodule

module dsc_vca (
	input  wire signed [15:0] signal,
	input  wire        [15:0] gain,
	output wire signed [15:0] out
);
	wire signed [32:0] product = signal * $signed({1'b0, gain});
	wire signed [16:0] scaled = product[32:16];

	assign out = (scaled >  17'sd32767) ?  16'sh7FFF :
	             (scaled < -17'sd32768) ? -16'sh8000 : scaled[15:0];
endmodule

// The torpedo and shot circuits clock a CD4024 and mix four divider taps.
module dsc_swept_divider (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire        restart,
	input  wire [15:0] freq_hz,
	output wire signed [15:0] out
);
	logic [31:0] phase;
	logic [6:0] count;
	wire [31:0] freq = {16'd0, freq_hz};

	// 2^32 / 48000 = 89478.485. This shift sum is 89472 (-0.0073%).
	wire [31:0] inc = (freq << 16) + (freq << 14) + (freq << 12)
	                       + (freq << 11) + (freq << 10) + (freq << 8)
	                       + (freq << 7);
	wire [32:0] phase_next = {1'b0, phase} + {1'b0, inc};

	always_ff @(posedge clk) begin
		if (reset || restart) begin
			phase <= '0;
			count <= '0;
		end else if (ce) begin
			phase <= phase_next[31:0];
			if (phase_next[32]) count <= count + 1'd1;
		end
	end

	wire signed [16:0] mix = (count[0] ? 17'sd2048  : -17'sd2048)
	                               + (count[1] ? 17'sd4096  : -17'sd4096)
	                               + (count[2] ? 17'sd16000 : -17'sd16000)
	                               + (count[3] ? 17'sd7000  : -17'sd7000);
	assign out = mix[15:0];
endmodule

`default_nettype wire
