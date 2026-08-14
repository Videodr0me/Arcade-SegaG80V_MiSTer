//============================================================================
//  Sega G-80 high-resolution vector presentation
//
//  Written 2026 by Videodr0me
//
//  Replays each authentic DDA carry at twice the coordinate and sample density.
//  Each vector starts at its doubled origin, and every second DDA update lands
//  on the exact doubled authentic point. The original X-Y sequencer and its
//  timing remain authoritative.
//============================================================================

`default_nettype none

module sega_xy_shadow
(
	input  wire        clk,
	input  wire        reset,
	input  wire        frame_start,
	input  wire        ce_2x,

	input  wire        segment_start,
	input  wire [11:0] segment_start_x,
	input  wire [11:0] segment_start_y,
	input  wire  [8:0] segment_duration,
	input  wire  [7:0] segment_delta_x,
	input  wire  [7:0] segment_delta_y,
	input  wire        segment_x_negative,
	input  wire        segment_y_negative,
	input  wire  [5:0] segment_colour,
	input  wire        segment_beam,
	input  wire        segment_dot,

	output wire signed [12:0] out_x,
	output wire signed [12:0] out_y,
	output wire  [5:0] out_colour,
	output wire        out_beam,
	output wire        out_valid,
	output logic       busy
);

	logic        segment_start_d;
	logic [12:0] position_x;
	logic [12:0] position_y;
	logic  [7:0] delta_x;
	logic  [7:0] delta_y;
	logic  [7:0] accumulator_x;
	logic  [7:0] accumulator_y;
	logic  [7:0] next_accumulator_x;
	logic  [7:0] next_accumulator_y;
	logic  [8:0] remaining;
	logic        carry_x;
	logic        carry_y;
	logic        x_negative;
	logic        y_negative;
	logic  [5:0] colour;
	logic        beam;
	logic  [1:0] dot_wait;
	logic        dot_pending;
	logic        half_step;
	logic        valid_started;
	logic        finish_pending;

	wire start_event = segment_start && !segment_start_d;

	function automatic logic signed [12:0] open_axis(input logic [11:0] raw);
		begin
			open_axis = $signed({1'b0, raw}) - 13'sd1024;
		end
	endfunction

	assign out_x = open_axis(position_x[11:0]);
	assign out_y = open_axis(position_y[11:0]);
	assign out_colour = colour;
	assign out_valid = valid_started || dot_pending;
	assign out_beam = out_valid && beam;

	always_ff @(posedge clk) begin : shadow_dda
		logic [8:0] sum_x;
		logic [8:0] sum_y;

		segment_start_d <= segment_start;
		dot_pending <= 1'b0;

		if (reset || frame_start) begin
			segment_start_d <= 1'b0;
			position_x <= 13'd0;
			position_y <= 13'd0;
			delta_x <= 8'd0;
			delta_y <= 8'd0;
			accumulator_x <= 8'd0;
			accumulator_y <= 8'd0;
			next_accumulator_x <= 8'd0;
			next_accumulator_y <= 8'd0;
			remaining <= 9'd0;
			carry_x <= 1'b0;
			carry_y <= 1'b0;
			x_negative <= 1'b0;
			y_negative <= 1'b0;
			colour <= 6'd0;
			beam <= 1'b0;
			dot_wait <= 2'd0;
			dot_pending <= 1'b0;
			half_step <= 1'b0;
			valid_started <= 1'b0;
			finish_pending <= 1'b0;
			busy <= 1'b0;
		end else if (start_event) begin
			position_x <= {segment_start_x, 1'b0};
			position_y <= {segment_start_y, 1'b0};
			delta_x <= segment_delta_x;
			delta_y <= segment_delta_y;
			accumulator_x <= 8'd0;
			accumulator_y <= 8'd0;
			next_accumulator_x <= 8'd0;
			next_accumulator_y <= 8'd0;
			remaining <= segment_duration;
			carry_x <= 1'b0;
			carry_y <= 1'b0;
			x_negative <= segment_x_negative;
			y_negative <= segment_y_negative;
			colour <= segment_colour;
			beam <= segment_beam;
			dot_wait <= segment_dot ? 2'd2 : 2'd0;
			half_step <= 1'b0;
			valid_started <= (segment_duration != 9'd0);
			finish_pending <= 1'b0;
			busy <= (segment_duration != 9'd0);
		end else if (finish_pending) begin
			finish_pending <= 1'b0;
			valid_started <= 1'b0;
			busy <= 1'b0;
		end else if (dot_wait != 2'd0 && ce_2x) begin
			dot_wait <= dot_wait - 2'd1;
			if (dot_wait == 2'd1)
				dot_pending <= 1'b1;
		end else if (busy && ce_2x) begin
			// Split each authentic DDA carry over two doubled-grid updates.
			if (!half_step) begin
				sum_x = {1'b0, accumulator_x} + {1'b0, delta_x}
				      + {8'd0, delta_x[7]};
				sum_y = {1'b0, accumulator_y} + {1'b0, delta_y}
				      + {8'd0, delta_y[7]};
				next_accumulator_x <= sum_x[7:0];
				next_accumulator_y <= sum_y[7:0];
				carry_x <= sum_x[8];
				carry_y <= sum_y[8];
				half_step <= 1'b1;
				if (sum_x[8])
					position_x <= x_negative ? position_x - 13'd1
					                                : position_x + 13'd1;
				if (sum_y[8])
					position_y <= y_negative ? position_y - 13'd1
					                                : position_y + 13'd1;
			end else begin
				if (carry_x)
					position_x <= x_negative ? position_x - 13'd1
					                                : position_x + 13'd1;
				if (carry_y)
					position_y <= y_negative ? position_y - 13'd1
					                                : position_y + 13'd1;
				accumulator_x <= next_accumulator_x;
				accumulator_y <= next_accumulator_y;
				remaining <= remaining - 9'd1;
				half_step <= 1'b0;
				valid_started <= 1'b1;
				if (remaining == 9'd1)
					finish_pending <= 1'b1;
			end
		end
	end

endmodule

`default_nettype wire
