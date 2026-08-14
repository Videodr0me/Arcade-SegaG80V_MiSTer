// ============================================================================
// Phosphor timing.
// Written 2026 by Videodr0me
// Measures the source frame rate and converts draw phases to physical age.
// ============================================================================

module vfb_phosphor_timing #(
	parameter [19:0] DEFAULT_LIST_CLKS = 20'd64452,
	parameter [15:0] AGE_QUANTUM_CLKS = 16'd3947,
	parameter [17:0] SYS_AGE_QUANTUM_CLKS = 18'd191364,
	parameter integer BUFFER_COUNT = 5,
	parameter integer BUF_IDX_W = 3
) (
	input  logic clk_source,
	input  logic source_tick,
	input  logic clk_sys,
	input  logic reset_source,
	input  logic reset_sys,
	input  logic frame_done,
	input  logic frame_start,

	input  logic eof_token_popped,
	input  logic [15:0] eof_frame_tick_clks_popped,
	input  logic [15:0] eof_elapsed_frame_tick_clks_popped,
	input  logic [BUF_IDX_W-1:0] buf_draw,
	input  logic [BUF_IDX_W-1:0] buf_display,
	input  logic vbl_swap_req,
	input  logic presentation_120hz,
	input  logic [1:0] BUFFER_MODE,

	input  logic        compose_req,
	input  logic [BUF_IDX_W-1:0] compose_buf,
	input  logic        raw_frame_dropped,
	input  logic [BUF_IDX_W-1:0] raw_frame_dropped_buf,
	output logic [2:0]  compose_draw_idx,
	output logic [31:0] compose_age_map,
	output logic [3:0]  compose_frame_age,
	output logic        compose_metadata_ready,

	output logic [2:0]  draw_idx,
	output logic [15:0] active_frame_tick_clks,
	output logic [15:0] completed_frame_tick_clks,
	output logic [2:0]  readout_draw_idx,
	output logic [31:0] readout_age_map
);

	localparam [19:0] DEFAULT_LIST_PERIOD =
		(DEFAULT_LIST_CLKS < 20'd8) ? 20'd8 : DEFAULT_LIST_CLKS;
	localparam [19:0] DEFAULT_PHASE_TICK_EXT =
		(DEFAULT_LIST_PERIOD + 20'd4) >> 3;
	localparam [15:0] DEFAULT_PHASE_TICK_CLKS =
		(DEFAULT_PHASE_TICK_EXT > 20'h0ffff)
			? 16'hffff : DEFAULT_PHASE_TICK_EXT[15:0];
	localparam [15:0] AGE_QUANTUM =
		(AGE_QUANTUM_CLKS == 16'd0) ? 16'd1 : AGE_QUANTUM_CLKS;
	localparam [16:0] AGE_QUANTUM_EXT = {1'b0, AGE_QUANTUM};
	localparam [16:0] AGE_HALF_QUANTUM = {1'b0, (AGE_QUANTUM >> 1)};
	localparam [17:0] SYS_DEFAULT_TICK_CLKS =
		(SYS_AGE_QUANTUM_CLKS == 18'd0) ? 18'd1 : SYS_AGE_QUANTUM_CLKS;
	localparam [17:0] SYS_HALF_QUANTUM = SYS_DEFAULT_TICK_CLKS >> 1;
	localparam [31:0] IDENTITY_AGE_MAP = 32'hECA86420;

	function automatic [15:0] frame_tick_from_period(input logic [19:0] period);
		logic [16:0] rounded_tick;
		begin
			if (period[19:3] >= 17'h0ffff) begin
				frame_tick_from_period = 16'hffff;
			end else begin
				rounded_tick = period[19:3] + {16'd0, period[2]};
				frame_tick_from_period = (rounded_tick == 17'd0)
					? 16'd1 : rounded_tick[15:0];
			end
		end
	endfunction

	function automatic [19:0] valid_list_period(input logic [19:0] period);
		begin
			valid_list_period = (period < 20'd8) ? 20'd8 : period;
		end
	endfunction

	logic        frame_done_q;
	logic        have_eof_reference;
	logic        list_active;
	logic        ignore_forced_done;
	logic [19:0] eof_period_count;
	logic [19:0] list_tick_count;
	logic [19:0] next_list_period;
	logic [19:0] active_list_period;
	logic [19:0] phase_remainder;
	logic [2:0]  draw_idx_source;

	wire frame_done_rise = frame_done && !frame_done_q;
	wire [20:0] phase_sum = {1'b0, phase_remainder} + 21'd8;
	wire [20:0] phase_difference =
		phase_sum - {1'b0, active_list_period};
	wire [19:0] restarted_list_period = valid_list_period(
		(list_tick_count == 20'hfffff)
			? list_tick_count : list_tick_count + 20'd1);
	wire [15:0] measured_elapsed_tick_clks =
		frame_tick_from_period(eof_period_count);

	assign active_frame_tick_clks = frame_tick_from_period(active_list_period);
	assign completed_frame_tick_clks = have_eof_reference
		? measured_elapsed_tick_clks : active_frame_tick_clks;

	always_ff @(posedge clk_source) begin
		if (reset_source) begin
			frame_done_q <= 1'b0;
			have_eof_reference <= 1'b0;
			list_active <= 1'b0;
			ignore_forced_done <= 1'b0;
			eof_period_count <= 20'd0;
			list_tick_count <= 20'd0;
			next_list_period <= DEFAULT_LIST_PERIOD;
			active_list_period <= DEFAULT_LIST_PERIOD;
			phase_remainder <= 20'd0;
			draw_idx_source <= 3'd0;
		end else begin
			frame_done_q <= frame_done;

			if (source_tick) begin
				if (eof_period_count != 20'hfffff)
					eof_period_count <= eof_period_count + 20'd1;

				if (list_active) begin
					if (list_tick_count != 20'hfffff)
						list_tick_count <= list_tick_count + 20'd1;

					if (phase_sum >= {1'b0, active_list_period}) begin
						phase_remainder <= phase_difference[19:0];
						if (draw_idx_source != 3'd7)
							draw_idx_source <= draw_idx_source + 3'd1;
					end else begin
						phase_remainder <= phase_sum[19:0];
					end
				end

				if (frame_start) begin
					list_active <= 1'b1;
					list_tick_count <= 20'd0;
					phase_remainder <= 20'd0;
					draw_idx_source <= 3'd0;

					if (list_active) begin
						// A busy generator is restarted at EDGINT. Its measured
						// duration is available for the new list immediately.
						next_list_period <= restarted_list_period;
						active_list_period <= restarted_list_period;
						ignore_forced_done <= 1'b1;
					end else begin
						active_list_period <= next_list_period;
					end
				end
			end

			// frame_done rises between VCL enables, so consume it here rather
			// than qualifying the edge with source_tick.
			if (frame_done_rise) begin
				have_eof_reference <= 1'b1;
				eof_period_count <= 20'd0;

				if (ignore_forced_done) begin
					ignore_forced_done <= 1'b0;
				end else if (list_active) begin
					list_active <= 1'b0;
					next_list_period <= valid_list_period(list_tick_count);
				end
			end
		end
	end

	logic [2:0] draw_idx_sync1;
	always_ff @(posedge clk_sys) begin
		if (reset_sys) begin
			draw_idx_sync1 <= 3'd0;
			draw_idx <= 3'd0;
		end else begin
			draw_idx_sync1 <= draw_idx_source;
			draw_idx <= draw_idx_sync1;
		end
	end

	logic [31:0] buf_age_map [0:BUFFER_COUNT-1];
	logic [3:0]  buf_frame_age [0:BUFFER_COUNT-1];
	logic [BUFFER_COUNT-1:0] buf_metadata_ready;
	// Capture skipped-frame age when composition starts. Frames dropped during
	// composition are carried into the following source frame.
	logic        compose_req_q;
	logic [3:0]  skipped_frame_age;
	logic [3:0]  compose_age_carry;
	logic        compose_age_carry_valid;

	logic                 map_pending;
	logic                 map_pending_store_buffer;
	logic [BUF_IDX_W-1:0] map_pending_buf;
	logic [15:0]          map_pending_tick;
	logic [15:0]          map_pending_elapsed_tick;
	logic                 map_busy;
	logic                 map_finishing_frame;
	logic                 map_build_store_buffer;
	logic [BUF_IDX_W-1:0] map_build_buf;
	logic [2:0]           map_build_index;
	logic [3:0]           map_build_age;
	logic [15:0]          map_build_tick;
	logic [15:0]          map_build_elapsed_tick;
	logic [20:0]          map_build_remainder;
	logic [31:0]          map_build_data;
	logic                 map_commit_pending;
	logic                 map_commit_store_buffer;
	logic [BUF_IDX_W-1:0] map_commit_buf;
	logic [31:0]          map_commit_data;
	logic [3:0]           map_commit_frame_age;
	logic [31:0]          latest_age_map;
	logic [BUF_IDX_W-1:0] prev_buf_display;
	logic                 have_vbl_reference;
	logic [17:0]          vbl_age_tick_count;
	logic [3:0]           vbl_elapsed_age;
	logic                 presentation_120hz_control_q = 1'b0;
	logic [1:0]           buffer_mode_q = 2'd0;
	logic                 presentation_120hz_q;
	logic                 presentation_vbl_half;

	always_ff @(posedge clk_sys) begin
		presentation_120hz_control_q <= presentation_120hz;
		buffer_mode_q <= BUFFER_MODE;
	end

	wire [15:0] popped_frame_tick_clks =
		(eof_frame_tick_clks_popped == 16'd0)
			? DEFAULT_PHASE_TICK_CLKS : eof_frame_tick_clks_popped;
	wire [15:0] popped_elapsed_frame_tick_clks =
		(eof_elapsed_frame_tick_clks_popped == 16'd0)
			? popped_frame_tick_clks : eof_elapsed_frame_tick_clks_popped;

	function automatic [3:0] saturating_age_sum(
		input logic [3:0] lhs,
		input logic [3:0] rhs
	);
		logic [4:0] sum;
		begin
			sum = {1'b0, lhs} + {1'b0, rhs};
			saturating_age_sum = (sum > 5'd15) ? 4'd15 : sum[3:0];
		end
	endfunction

	function automatic [15:0] phase_prng_next(input logic [15:0] state);
		begin
			phase_prng_next = {
				state[14:0],
				state[15] ^ state[13] ^ state[12] ^ state[10]
			};
		end
	endfunction

	logic [15:0] readout_phase_prng;
	logic [15:0] compose_phase_prng;
	wire [15:0] readout_phase_prng_next =
		phase_prng_next(readout_phase_prng);
	wire [15:0] compose_phase_prng_next =
		phase_prng_next(compose_phase_prng);

	// If a frame is dropped, use maximum age instead.
	wire [3:0] dropped_frame_age =
		buf_metadata_ready[raw_frame_dropped_buf]
			? buf_frame_age[raw_frame_dropped_buf] : 4'd15;

	always_comb begin
		compose_age_map = buf_age_map[compose_buf];
		compose_frame_age = saturating_age_sum(
			buf_frame_age[compose_buf],
			compose_age_carry_valid ? compose_age_carry : 4'd0);
		compose_metadata_ready = buf_metadata_ready[compose_buf] &&
			(!compose_req || compose_age_carry_valid);
	end

	always_ff @(posedge clk_sys) begin
		if (reset_sys) begin
			compose_req_q <= 1'b0;
			skipped_frame_age <= 4'd0;
			compose_age_carry <= 4'd0;
			compose_age_carry_valid <= 1'b0;
			map_pending <= 1'b0;
			map_pending_store_buffer <= 1'b0;
			map_pending_buf <= '0;
			map_pending_tick <= DEFAULT_PHASE_TICK_CLKS;
			map_pending_elapsed_tick <= DEFAULT_PHASE_TICK_CLKS;
			map_busy <= 1'b0;
			map_finishing_frame <= 1'b0;
			map_build_store_buffer <= 1'b0;
			map_build_buf <= '0;
			map_build_index <= 3'd0;
			map_build_age <= 4'd0;
			map_build_tick <= DEFAULT_PHASE_TICK_CLKS;
			map_build_elapsed_tick <= DEFAULT_PHASE_TICK_CLKS;
			map_build_remainder <= 21'd0;
			map_build_data <= 32'd0;
			map_commit_pending <= 1'b0;
			map_commit_store_buffer <= 1'b0;
			map_commit_buf <= '0;
			map_commit_data <= 32'd0;
			map_commit_frame_age <= 4'd0;
			latest_age_map <= IDENTITY_AGE_MAP;
			prev_buf_display <= '0;
			have_vbl_reference <= 1'b0;
			vbl_age_tick_count <= SYS_HALF_QUANTUM;
			vbl_elapsed_age <= 4'd0;
			presentation_120hz_q <= 1'b0;
			presentation_vbl_half <= 1'b0;
			readout_draw_idx <= 3'd0;
			compose_draw_idx <= 3'd0;
			readout_phase_prng <= 16'h1ace;
			compose_phase_prng <= 16'hbeef;
			readout_age_map <= IDENTITY_AGE_MAP;
			buf_metadata_ready <= '0;
			for (int i = 0; i < BUFFER_COUNT; i++) begin
				buf_age_map[i] <= IDENTITY_AGE_MAP;
				buf_frame_age[i] <= 4'd0;
			end
		end else begin
			compose_req_q <= compose_req;
			presentation_120hz_q <= presentation_120hz_control_q;

			// In VBL-only mode, derive age from display swaps instead of EOF.
			if (buffer_mode_q != 2'd1) begin
				have_vbl_reference <= 1'b0;
				vbl_age_tick_count <= SYS_HALF_QUANTUM;
				vbl_elapsed_age <= 4'd0;
			end else if (vbl_swap_req) begin
				have_vbl_reference <= 1'b1;
				vbl_age_tick_count <= SYS_HALF_QUANTUM;
				vbl_elapsed_age <= 4'd0;
			end else if (have_vbl_reference &&
			             (vbl_age_tick_count >= SYS_DEFAULT_TICK_CLKS - 18'd1)) begin
				vbl_age_tick_count <= 18'd0;
				if (vbl_elapsed_age != 4'd15)
					vbl_elapsed_age <= vbl_elapsed_age + 4'd1;
			end else if (have_vbl_reference) begin
				vbl_age_tick_count <= vbl_age_tick_count + 18'd1;
			end

			if (!compose_req)
				compose_age_carry_valid <= 1'b0;

			if (compose_req && !compose_req_q) begin
				compose_phase_prng <= compose_phase_prng_next;
				compose_draw_idx <= compose_phase_prng_next[2:0];
				compose_age_carry <= skipped_frame_age;
				compose_age_carry_valid <= 1'b1;
				skipped_frame_age <= raw_frame_dropped
					? dropped_frame_age : 4'd0;
			end else if (raw_frame_dropped) begin
				skipped_frame_age <= saturating_age_sum(
					skipped_frame_age, dropped_frame_age);
			end

			if (presentation_120hz_control_q != presentation_120hz_q) begin
				presentation_vbl_half <= 1'b0;
			end else if (vbl_swap_req) begin
				if (presentation_120hz_control_q) begin
					presentation_vbl_half <= ~presentation_vbl_half;
					if (!presentation_vbl_half) begin
						readout_phase_prng <= readout_phase_prng_next;
						readout_draw_idx <= readout_phase_prng_next[2:0];
					end
				end else begin
					presentation_vbl_half <= 1'b0;
					readout_phase_prng <= readout_phase_prng_next;
					readout_draw_idx <= readout_phase_prng_next[2:0];
				end
			end

			prev_buf_display <= buf_display;
			if (vbl_swap_req || (buf_display != prev_buf_display)) begin
				readout_age_map <= buf_age_map[buf_display];
			end

			if (map_commit_pending) begin
				latest_age_map <= map_commit_data;
				if (map_commit_store_buffer) begin
					buf_age_map[map_commit_buf] <= map_commit_data;
					buf_frame_age[map_commit_buf] <= map_commit_frame_age;
					buf_metadata_ready[map_commit_buf] <= 1'b1;
				end
				map_commit_pending <= 1'b0;
				map_busy <= 1'b0;
			end else if (!map_busy && map_pending) begin
				map_pending <= 1'b0;
				map_busy <= 1'b1;
				map_finishing_frame <= 1'b0;
				map_build_store_buffer <= map_pending_store_buffer;
				map_build_buf <= map_pending_buf;
				map_build_index <= 3'd1;
				map_build_age <= 4'd0;
				map_build_tick <= map_pending_tick;
				map_build_elapsed_tick <= map_pending_elapsed_tick;
				map_build_remainder <= AGE_HALF_QUANTUM
					+ {5'd0, map_pending_tick};
				map_build_data <= 32'd0;
			end else if (map_busy) begin
				if ((map_build_age == 4'd15) ||
				    (map_build_remainder < AGE_QUANTUM_EXT)) begin
					if (map_finishing_frame) begin
						map_commit_pending <= 1'b1;
						map_commit_store_buffer <= map_build_store_buffer &&
							(buffer_mode_q != 2'd1);
						map_commit_buf <= map_build_buf;
						map_commit_data <= map_build_data;
						map_commit_frame_age <= map_build_age;
					end else if (map_build_index == 3'd7) begin
						map_build_data <=
							{map_build_age, map_build_data[27:0]};
						map_build_age <= 4'd0;
						map_build_remainder <= AGE_HALF_QUANTUM
							+ {2'b00, map_build_elapsed_tick, 3'b000};
						map_finishing_frame <= 1'b1;
					end else begin
						map_build_data[{map_build_index, 2'b00} +: 4]
							<= map_build_age;
						map_build_index <= map_build_index + 3'd1;
						if (map_build_age != 4'd15)
							map_build_remainder <= map_build_remainder
								+ {5'd0, map_build_tick};
					end
				end else begin
					map_build_remainder <= map_build_remainder - AGE_QUANTUM_EXT;
					map_build_age <= map_build_age + 4'd1;
				end
			end

			if (eof_token_popped) begin
				map_pending_buf <= buf_draw;
				map_pending_tick <= popped_frame_tick_clks;
				map_pending_elapsed_tick <= popped_elapsed_frame_tick_clks;
				map_pending_store_buffer <= (buffer_mode_q != 2'd1);
				map_pending <= 1'b1;
				if (buffer_mode_q != 2'd1) begin
					buf_metadata_ready[buf_draw] <= 1'b0;
				end
			end

			if ((buffer_mode_q == 2'd1) && vbl_swap_req) begin
				buf_age_map[buf_draw] <= latest_age_map;
				buf_frame_age[buf_draw] <= have_vbl_reference
					? vbl_elapsed_age : 4'd0;
				buf_metadata_ready[buf_draw] <= 1'b1;
			end
		end
	end

endmodule
