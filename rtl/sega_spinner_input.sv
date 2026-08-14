//============================================================================
//  Sega G-80 spinner input adapter
//
//  The original counter always advances by movement magnitude and stores the
//  direction of the latest edge. Relative devices therefore remain separate
//  from the continuous button and analog-stick rate generator.
//============================================================================

`default_nettype none

module sega_spinner_input #(
	parameter logic [25:0] CLK_HZ = 26'd15_468_480
)(
	input  wire               clk,
	input  wire               reset,
	input  wire         [2:0] game,
	input  wire               move_left,
	input  wire               move_right,
	input  wire signed  [7:0] analog_x_0,
	input  wire signed  [7:0] analog_x_1,
	input  wire         [8:0] spinner_0,
	input  wire         [8:0] spinner_1,
	input  wire        [24:0] mouse,
	input  wire               reverse,
	input  wire         [2:0] sensitivity,
	output logic              step_valid,
	output logic        [8:0] step_magnitude,
	output logic              step_direction
);

	localparam logic [7:0] ANALOG_DEAD_ZONE = 8'd16;
	localparam logic [6:0] RATE_COMMAND_MAX = 7'd111;
	localparam logic [20:0] RATE_LIMIT = 21'd1_776_000;

	function automatic logic [8:0] abs_delta(input logic signed [8:0] value);
		begin
			abs_delta = value[8] ? $unsigned(-value) : $unsigned(value);
		end
	endfunction

	function automatic logic [7:0] abs_axis(input logic signed [7:0] value);
		begin
			if (value == 8'sh80)
				abs_axis = 8'd127;
			else
				abs_axis = value[7] ? $unsigned(-value) : $unsigned(value);
		end
	endfunction

	// Q4 counts preserve fractional sensitivity gains between reports.
	function automatic logic [13:0] scale_q4(
		input logic [8:0] magnitude,
		input logic [2:0] gain
	);
		logic [13:0] magnitude_ext;
		begin
			magnitude_ext = {5'd0, magnitude};
			case (gain)
				3'd0: scale_q4 = magnitude_ext << 4;
				3'd1: scale_q4 = (magnitude_ext << 3) + (magnitude_ext << 2);
				3'd2: scale_q4 = magnitude_ext << 3;
				3'd3: scale_q4 = magnitude_ext << 2;
				3'd4: scale_q4 = magnitude_ext << 1;
				3'd5: scale_q4 = (magnitude_ext << 4) + (magnitude_ext << 2);
				3'd6: scale_q4 = (magnitude_ext << 4) + (magnitude_ext << 3);
				default: scale_q4 = magnitude_ext << 5;
			endcase
		end
	endfunction

	logic        [8:0] spinner_q [0:1];
	logic       [24:0] mouse_q;
	logic signed [7:0] analog_q [0:1];
	logic        [1:0] move_q;
	logic              reverse_q;
	logic        [2:0] sensitivity_q;
	logic        [2:0] game_q;

	logic        [1:0] arm_count;
	logic              input_ready;
	logic        [1:0] spinner_toggle_seen;
	logic              mouse_toggle_seen;
	logic              reverse_previous;
	logic        [2:0] sensitivity_previous;
	logic        [2:0] game_previous;

	logic        [3:0] relative_remainder [0:1];
	logic        [5:0] mouse_remainder;
	logic        [2:0] relative_pending;
	logic        [8:0] pending_magnitude [0:2];
	logic              pending_direction [0:2];
	logic              rate_pending;
	logic              rate_pending_direction;

	logic       [24:0] tick_phase;
	logic       [25:0] tick_sum;
	logic       [25:0] tick_remainder;
	logic       [24:0] tick_phase_next;
	logic              rate_tick;
	logic       [20:0] rate_phase;
	logic       [21:0] rate_sum;
	logic       [21:0] rate_remainder;
	logic              rate_active;
	logic              rate_direction_previous;

	logic signed [8:0] spinner_delta [0:1];
	logic signed [8:0] mouse_delta;
	logic        [8:0] relative_magnitude [0:1];
	logic       [13:0] relative_scaled [0:1];
	logic       [13:0] relative_sum [0:1];
	logic        [8:0] relative_steps [0:1];
	logic              relative_direction [0:1];
	logic        [8:0] mouse_magnitude;
	logic       [13:0] mouse_scale_q4;
	logic       [14:0] mouse_scaled_q6;
	logic       [14:0] mouse_sum_q6;
	logic        [8:0] mouse_steps;
	logic              mouse_direction;

	logic        [7:0] analog_magnitude [0:1];
	logic        [6:0] rate_command;
	logic              rate_direction;
	logic       [13:0] rate_command_q4;
	logic       [20:0] rate_command_ext;
	logic       [20:0] rate_increment;
	logic              mode_changed;

	integer comb_channel;
	always_comb begin
		spinner_delta[0] = $signed({spinner_q[0][7], spinner_q[0][7:0]});
		spinner_delta[1] = $signed({spinner_q[1][7], spinner_q[1][7:0]});
		mouse_delta = $signed({mouse_q[4], mouse_q[15:8]});

		for (comb_channel = 0; comb_channel < 2; comb_channel = comb_channel + 1) begin
			relative_magnitude[comb_channel] = abs_delta(spinner_delta[comb_channel]);
			relative_scaled[comb_channel] = scale_q4(relative_magnitude[comb_channel],
			                                              sensitivity_q);
			relative_sum[comb_channel] = relative_scaled[comb_channel] +
			                             {10'd0, relative_remainder[comb_channel]};
			relative_steps[comb_channel] = relative_sum[comb_channel][12:4];
			relative_direction[comb_channel] =
				spinner_delta[comb_channel][8] ^ reverse_q;
		end

		mouse_magnitude = abs_delta(mouse_delta);
		mouse_scale_q4 = scale_q4(mouse_magnitude, sensitivity_q);
		// Mouse uses half spinner gain; Tac/Scan uses 75% of that mouse rate.
		mouse_scaled_q6 = (game_q == sega_game_pkg::GAME_TACSCAN) ?
		                  ({1'b0, mouse_scale_q4} +
		                   {2'b00, mouse_scale_q4[13:1]}) :
		                  {mouse_scale_q4, 1'b0};
		mouse_sum_q6 = mouse_scaled_q6 + {9'd0, mouse_remainder};
		mouse_steps = mouse_sum_q6[14:6];
		mouse_direction = mouse_delta[8] ^ reverse_q;

		analog_magnitude[0] = abs_axis(analog_q[0]);
		analog_magnitude[1] = abs_axis(analog_q[1]);
		rate_command = 7'd0;
		rate_direction = 1'b0;
		if (move_q != 2'b00) begin
			if (move_q == 2'b01) begin
				rate_command = RATE_COMMAND_MAX;
				rate_direction = 1'b1;
			end else if (move_q == 2'b10) begin
				rate_command = RATE_COMMAND_MAX;
				rate_direction = 1'b0;
			end
		end else if ((analog_magnitude[0] > ANALOG_DEAD_ZONE) ||
		             (analog_magnitude[1] > ANALOG_DEAD_ZONE)) begin
			if (analog_magnitude[1] > analog_magnitude[0]) begin
				rate_command = analog_magnitude[1][6:0] - ANALOG_DEAD_ZONE[6:0];
				rate_direction = analog_q[1][7];
			end else begin
				rate_command = analog_magnitude[0][6:0] - ANALOG_DEAD_ZONE[6:0];
				rate_direction = analog_q[0][7];
			end
		end
		rate_direction = rate_direction ^ reverse_q;

		rate_command_q4 = scale_q4({2'b00, rate_command}, sensitivity_q);
		rate_command_ext = {7'd0, rate_command_q4};
		case (game_q)
			sega_game_pkg::GAME_ZEKTOR:
				rate_increment = (rate_command_ext << 7) -
				                 (rate_command_ext << 3);
			sega_game_pkg::GAME_TACSCAN:
				// Tac/Scan software controls use their 75% rate coefficient.
				rate_increment = (rate_command_ext << 8) +
				                 (rate_command_ext << 5) +
				                 (rate_command_ext << 3) +
				                 (rate_command_ext << 2);
			sega_game_pkg::GAME_STARTREK:
				rate_increment = (rate_command_ext << 8) +
				                 (rate_command_ext << 7) +
				                 (rate_command_ext << 4);
			default: rate_increment = 21'd0;
		endcase

		tick_sum = {1'b0, tick_phase} + 26'd1_000;
		rate_tick = (tick_sum >= CLK_HZ);
		tick_remainder = tick_sum - CLK_HZ;
		tick_phase_next = rate_tick ?
		                  tick_remainder[24:0] : tick_sum[24:0];
		rate_sum = {1'b0, rate_phase} + {1'b0, rate_increment};
		rate_remainder = rate_sum - {1'b0, RATE_LIMIT};
		mode_changed = (reverse_q != reverse_previous) ||
		               (sensitivity_q != sensitivity_previous) ||
		               (game_q != game_previous);
	end

	integer seq_channel;
	always_ff @(posedge clk) begin
		if (reset) begin
			spinner_q[0] <= 9'd0;
			spinner_q[1] <= 9'd0;
			mouse_q <= 25'd0;
			analog_q[0] <= 8'sd0;
			analog_q[1] <= 8'sd0;
			move_q <= 2'b00;
			reverse_q <= 1'b0;
			sensitivity_q <= 3'd0;
			game_q <= 3'd0;
			arm_count <= 2'd0;
			input_ready <= 1'b0;
			spinner_toggle_seen <= 2'b00;
			mouse_toggle_seen <= 1'b0;
			reverse_previous <= 1'b0;
			sensitivity_previous <= 3'd0;
			game_previous <= 3'd0;
			for (seq_channel = 0; seq_channel < 2; seq_channel = seq_channel + 1)
				relative_remainder[seq_channel] <= 4'd0;
			mouse_remainder <= 6'd0;
			for (seq_channel = 0; seq_channel < 3; seq_channel = seq_channel + 1) begin
				pending_magnitude[seq_channel] <= 9'd0;
				pending_direction[seq_channel] <= 1'b0;
			end
			relative_pending <= 3'b000;
			rate_pending <= 1'b0;
			rate_pending_direction <= 1'b0;
			tick_phase <= 25'd0;
			rate_phase <= 21'd0;
			rate_active <= 1'b0;
			rate_direction_previous <= 1'b0;
			step_valid <= 1'b0;
			step_magnitude <= 9'd0;
			step_direction <= 1'b0;
		end else begin
			spinner_q[0] <= spinner_0;
			spinner_q[1] <= spinner_1;
			mouse_q <= mouse;
			analog_q[0] <= analog_x_0;
			analog_q[1] <= analog_x_1;
			move_q <= {move_right, move_left};
			reverse_q <= reverse;
			sensitivity_q <= sensitivity;
			game_q <= game;
			tick_phase <= tick_phase_next;
			step_valid <= 1'b0;

			if (!input_ready) begin
				spinner_toggle_seen <= {spinner_q[1][8], spinner_q[0][8]};
				mouse_toggle_seen <= mouse_q[24];
				reverse_previous <= reverse_q;
				sensitivity_previous <= sensitivity_q;
				game_previous <= game_q;
				arm_count <= arm_count + 1'd1;
				if (&arm_count)
					input_ready <= 1'b1;
			end else begin
				spinner_toggle_seen <= {spinner_q[1][8], spinner_q[0][8]};
				mouse_toggle_seen <= mouse_q[24];
				reverse_previous <= reverse_q;
				sensitivity_previous <= sensitivity_q;
				game_previous <= game_q;

				if (mode_changed) begin
					relative_pending <= 3'b000;
					rate_pending <= 1'b0;
					rate_phase <= 21'd0;
					rate_active <= 1'b0;
					for (seq_channel = 0; seq_channel < 2;
					     seq_channel = seq_channel + 1)
						relative_remainder[seq_channel] <= 4'd0;
					mouse_remainder <= 6'd0;
				end else begin
					if (relative_pending[0]) begin
						step_valid <= 1'b1;
						step_magnitude <= pending_magnitude[0];
						step_direction <= pending_direction[0];
						relative_pending[0] <= 1'b0;
					end else if (relative_pending[1]) begin
						step_valid <= 1'b1;
						step_magnitude <= pending_magnitude[1];
						step_direction <= pending_direction[1];
						relative_pending[1] <= 1'b0;
					end else if (relative_pending[2]) begin
						step_valid <= 1'b1;
						step_magnitude <= pending_magnitude[2];
						step_direction <= pending_direction[2];
						relative_pending[2] <= 1'b0;
					end else if (rate_pending) begin
						step_valid <= 1'b1;
						step_magnitude <= 9'd1;
						step_direction <= rate_pending_direction;
						rate_pending <= 1'b0;
					end

					if (spinner_q[0][8] != spinner_toggle_seen[0]) begin
						relative_remainder[0] <= relative_sum[0][3:0];
						if ((relative_magnitude[0] != 0) &&
						    (relative_steps[0] != 0)) begin
							relative_pending[0] <= 1'b1;
							pending_magnitude[0] <= relative_steps[0];
							pending_direction[0] <= relative_direction[0];
						end
					end

					if (spinner_q[1][8] != spinner_toggle_seen[1]) begin
						relative_remainder[1] <= relative_sum[1][3:0];
						if ((relative_magnitude[1] != 0) &&
						    (relative_steps[1] != 0)) begin
							relative_pending[1] <= 1'b1;
							pending_magnitude[1] <= relative_steps[1];
							pending_direction[1] <= relative_direction[1];
						end
					end

					if (mouse_q[24] != mouse_toggle_seen) begin
						mouse_remainder <= mouse_sum_q6[5:0];
						if ((mouse_magnitude != 0) && (mouse_steps != 0)) begin
							relative_pending[2] <= 1'b1;
							pending_magnitude[2] <= mouse_steps;
							pending_direction[2] <= mouse_direction;
						end
					end

					if (rate_command == 0) begin
						rate_phase <= 21'd0;
						rate_active <= 1'b0;
					end else if (!rate_active ||
					             (rate_direction != rate_direction_previous)) begin
						rate_phase <= 21'd0;
						rate_active <= 1'b1;
						rate_direction_previous <= rate_direction;
					end else if (rate_tick) begin
						if (rate_sum >= {1'b0, RATE_LIMIT}) begin
							rate_phase <= rate_remainder[20:0];
							rate_pending <= 1'b1;
							rate_pending_direction <= rate_direction;
						end else begin
							rate_phase <= rate_sum[20:0];
						end
					end
				end
			end
		end
	end

endmodule

`default_nettype wire
