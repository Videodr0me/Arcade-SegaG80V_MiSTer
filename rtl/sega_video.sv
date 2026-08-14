//============================================================================
//  Sega G-80 X-Y video timing, geometry, and framebuffer integration
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_video
#(
	parameter logic [24:0] HEIGHT_STABLE_CYCLES = 25'd25_000_000
)
(
	input  wire        clk_master,  // 15.46848 MHz Sega machine domain
	input  wire        vec_tick,    // VCL step enable within clk_master
	input  wire        clk_50,
	input  wire        clk_125,
	input  wire        reset,
	input  wire        upload_reset,
	input  wire        reset_source,

	input  wire        direct_video,
	input  wire        direct_video_31khz,
	input  wire        crt_15khz_480i,
	input  wire [11:0] hdmi_height,
	input  wire  [1:0] aspect_ratio,
	input  wire  [2:0] game_orientation,
	input  wire  [1:0] screen_rotation,
	input  wire  [1:0] open_matte,

	// vector input from segag80v
	input  wire signed [12:0] vec_x,
	input  wire signed [12:0] vec_y,
	input  wire  [5:0] vec_colour,
	input  wire        vec_beam,
	input  wire        vec_valid,
	input  wire        frame_done,
	input  wire        frame_start,

	// OSD
	input  wire  [7:0] osd_flash_param,
	input  wire        osd_120hz,
	input  wire  [1:0] osd_buffer_mode,
	input  wire  [2:0] profile,
	input  wire [29:0] custom_1_settings,
	input  wire [29:0] custom_2_settings,

	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output wire         ce_pixel,
	output wire         hblank,
	output wire         vblank,
	output wire   [7:0] video_r,
	output wire   [7:0] video_g,
	output wire   [7:0] video_b,
	output wire         hsync,
	output wire         vsync,
	output wire         field,
	output wire         mode_supports_120hz,
	output wire         mode_is_15khz,
	output wire         video_mode_toggle,
	output wire         video_freeze,
	output wire         fifo_full,

	// DDRAM
	output wire         ddram_clk,
	input  wire         ddram_busy,
	output wire   [7:0] ddram_burst_count,
	output wire  [28:0] ddram_address,
	input  wire  [63:0] ddram_data_out,
	input  wire         ddram_data_ready,
	output wire         ddram_read,
	output wire  [63:0] ddram_data_in,
	output wire   [7:0] ddram_byte_enable,
	output wire         ddram_write,

	// SDRAM (halo alignment delay)
	input  wire  [15:0] sdram_data_in,
	output wire  [15:0] sdram_data_out,
	output wire         sdram_data_oe,
	output wire         sdram_cke,
	output wire         sdram_ncs,
	output wire         sdram_nras,
	output wire         sdram_ncas,
	output wire         sdram_nwe,
	output wire   [1:0] sdram_dqm,
	output wire  [12:0] sdram_address,
	output wire   [1:0] sdram_bank
);

	// HDMI height can change while the framework settles at startup.
	logic [11:0] height_meta_50 = 12'd0;
	logic [11:0] height_sync_50 = 12'd0;
	logic [11:0] height_candidate_50 = 12'd0;
	logic [11:0] height_stable_50 = 12'd0;
	logic [24:0] height_timer_50 = 25'd0;
	logic direct_video_meta_50 = 1'b0, direct_video_sync_50 = 1'b0;
	logic direct_31khz_meta_50 = 1'b0, direct_31khz_sync_50 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic upload_reset_50_meta = 1'b1, upload_reset_50 = 1'b1;
	wire [11:0] requested_height_50 = direct_video_sync_50 ?
		(direct_31khz_sync_50 ? 12'd480 : 12'd240) : hdmi_height;

	always_ff @(posedge clk_50) begin
		upload_reset_50_meta <= upload_reset;
		upload_reset_50 <= upload_reset_50_meta;
		direct_video_meta_50 <= direct_video;
		direct_video_sync_50 <= direct_video_meta_50;
		direct_31khz_meta_50 <= direct_video_31khz;
		direct_31khz_sync_50 <= direct_31khz_meta_50;
		height_meta_50 <= requested_height_50;
		height_sync_50 <= height_meta_50;
		if (upload_reset_50) begin
			height_candidate_50 <= 12'd0;
			height_stable_50 <= 12'd0;
			height_timer_50 <= 25'd0;
		end else if ((height_sync_50 <= 12'd200) ||
		    (height_sync_50 != height_candidate_50)) begin
			height_candidate_50 <= height_sync_50;
			height_timer_50 <= 25'd0;
		end else if (height_candidate_50 != height_stable_50) begin
			if (height_timer_50 < HEIGHT_STABLE_CYCLES - 1'd1)
				height_timer_50 <= height_timer_50 + 1'd1;
			else begin
				height_stable_50 <= height_candidate_50;
				height_timer_50 <= 25'd0;
			end
		end else begin
			height_timer_50 <= 25'd0;
		end
	end

	wire [21:0] control_in = {
		height_stable_50,
		osd_120hz,
		(profile == 3'd0),
		direct_video,
		direct_video_31khz,
		crt_15khz_480i,
		game_orientation,
		screen_rotation
	};
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [21:0] control_meta = '0, control_sync = '0;
	logic [21:0] control_sync_d = '0;
	logic [21:0] control_stable = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic upload_reset_125_meta = 1'b1, upload_reset_125 = 1'b1;

	always_ff @(posedge clk_125) begin
		upload_reset_125_meta <= upload_reset;
		upload_reset_125 <= upload_reset_125_meta;
		control_meta <= control_in;
		control_sync <= control_meta;
		control_sync_d <= control_sync;
		if (control_sync == control_sync_d)
			control_stable <= control_sync;
	end

	typedef struct packed {
		logic [11:0] height;
		logic        mode_120hz;
		logic        interlaced;
	} mode_key_t;

	localparam logic [1:0] PIXEL_FULL = 2'd0;
	localparam logic [1:0] PIXEL_HALF = 2'd1;
	localparam logic [1:0] PIXEL_FRACTIONAL = 2'd2;

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] center_x;
		logic [11:0] center_y;
		logic  [5:0] scale_normal;
		logic  [5:0] scale_swapped;
		logic [12:0] optimized_arx;
		logic [12:0] optimized_ary;
		logic [11:0] h_total;
		logic [11:0] v_total;
		logic [11:0] hs_start;
		logic [11:0] hs_end;
		logic [11:0] vs_start;
		logic [11:0] vs_end;
		logic  [1:0] pixel_mode;
		logic [17:0] pixel_step;
		logic [17:0] pixel_wrap;
		logic        is_1080p;
		logic        is_720p;
		logic        is_480p;
		logic        is_240p;
		logic        is_120hz;
		logic        is_interlaced;
	} video_mode_t;

	function automatic video_mode_t decode_video_mode(
		input logic [11:0] height,
		input logic        requested_120hz,
		input logic        requested_interlace
	);
		video_mode_t mode;
		begin
			mode = '0;
			mode.fb_width = 12'd916;
			mode.fb_height = 12'd720;
			mode.center_x = 12'd458;
			mode.center_y = 12'd360;
			mode.scale_normal = 6'd26;
			mode.scale_swapped = 6'd22;
			mode.optimized_arx = (height >= 12'd1440) ?
				(13'h1000 | 13'd1832) : (13'h1000 | 13'd916);
			mode.optimized_ary = (height >= 12'd1440) ?
				(13'h1000 | 13'd1440) : (13'h1000 | 13'd720);
			mode.h_total = 12'd1388;
			mode.v_total = 12'd748;
			mode.hs_start = 12'd1108;
			mode.hs_end = 12'd1196;
			mode.vs_start = 12'd728;
			mode.vs_end = 12'd733;
			mode.pixel_mode = requested_120hz ? PIXEL_FULL : PIXEL_HALF;
			mode.is_720p = 1'b1;
			mode.is_120hz = requested_120hz;

			if ((height >= 12'd1080) && (height < 12'd1400)) begin
				mode.fb_width = 12'd1360;
				mode.fb_height = 12'd1080;
				mode.center_x = 12'd680;
				mode.center_y = 12'd540;
				mode.scale_normal = 6'd40;
				mode.scale_swapped = 6'd32;
				mode.optimized_arx = 13'h1000 | 13'd1360;
				mode.optimized_ary = 13'h1000 | 13'd1080;
				mode.h_total = 12'd1851;
				mode.v_total = 12'd1124;
				mode.hs_start = 12'd1600;
				mode.hs_end = 12'd1688;
				mode.vs_start = 12'd1088;
				mode.vs_end = 12'd1093;
				mode.pixel_mode = PIXEL_FULL;
				mode.is_1080p = 1'b1;
				mode.is_720p = 1'b0;
				mode.is_120hz = 1'b0;
			end else if (height < 12'd480) begin
				mode.fb_width = 12'd720;
				mode.fb_height = 12'd240;
				mode.center_x = 12'd360;
				mode.center_y = 12'd120;
				mode.scale_normal = 6'd18;
				mode.scale_swapped = 6'd14;
				mode.optimized_arx = 13'h1000 | 13'd720;
				mode.optimized_ary = 13'h1000 | 13'd240;
				mode.h_total = 12'd883;
				mode.v_total = 12'd263;
				mode.hs_start = 12'd755;
				mode.hs_end = 12'd821;
				mode.vs_start = 12'd246;
				mode.vs_end = 12'd249;
				mode.pixel_mode = PIXEL_FRACTIONAL;
				mode.pixel_step = 18'd2448;
				mode.pixel_wrap = 18'd19427;
				mode.is_720p = 1'b0;
				mode.is_240p = 1'b1;
				mode.is_120hz = 1'b0;
			end else if (height < 12'd720) begin
				mode.fb_width = 12'd720;
				mode.fb_height = 12'd480;
				mode.center_x = 12'd360;
				mode.center_y = 12'd240;
				mode.scale_normal = 6'd18;
				mode.scale_swapped = 6'd14;
				mode.optimized_arx = 13'h1000 | 13'd720;
				mode.optimized_ary = 13'h1000 | 13'd480;
				mode.h_total = 12'd883;
				mode.v_total = 12'd528;
				mode.hs_start = 12'd755;
				mode.hs_end = 12'd821;
				mode.vs_start = 12'd493;
				mode.vs_end = 12'd499;
				mode.pixel_mode = PIXEL_FRACTIONAL;
				mode.pixel_step = 18'd53958;
				mode.pixel_wrap = 18'd186667;
				mode.is_720p = 1'b0;
				mode.is_480p = 1'b1;
				mode.is_120hz = 1'b0;
				mode.is_interlaced = requested_interlace;
			end

			decode_video_mode = mode;
		end
	endfunction

	function automatic logic [1:0] height_class(input logic [11:0] height);
		begin
			if (height < 12'd480)
				height_class = 2'd0;
			else if (height < 12'd720)
				height_class = 2'd1;
			else if ((height >= 12'd1080) && (height < 12'd1400))
				height_class = 2'd3;
			else
				height_class = 2'd2;
		end
	endfunction

	wire [11:0] stable_height = control_stable[21:10];
	wire stable_120hz = control_stable[9];
	wire request_bypass = control_stable[8];
	wire stable_direct_video = control_stable[7];
	wire stable_direct_31khz = control_stable[6];
	wire stable_480i = control_stable[5];
	wire [2:0] stable_game_orientation = control_stable[4:2];
	wire [1:0] stable_screen_rotation = control_stable[1:0];
	wire effective_swap = stable_game_orientation[2] ^
	                      stable_screen_rotation[0];
	wire height_supports_120hz = !stable_direct_video &&
	                             (stable_height >= 12'd720) &&
	                             (stable_height <= 12'd768);
	logic [11:0] request_height;
	logic request_interlaced;

	always_comb begin
		request_height = stable_height;
		request_interlaced = 1'b0;
		if (stable_direct_video) begin
			request_height = stable_direct_31khz ? 12'd480 :
			                 (stable_480i ? 12'd480 : 12'd240);
			request_interlaced = !stable_direct_31khz && stable_480i;
		end else if (stable_height < 12'd480) begin
			request_height = stable_480i ? 12'd480 : 12'd240;
			request_interlaced = stable_480i;
		end
	end

	wire request_120hz = stable_120hz && height_supports_120hz;
	wire request_valid = stable_height > 12'd200;
	mode_key_t request_key;
	video_mode_t requested_mode;
	assign request_key = {
		request_height,
		request_120hz,
		request_interlaced
	};
	always_comb requested_mode = decode_video_mode(
		request_height, request_120hz, request_interlaced);

	typedef enum logic [2:0] {
		MODE_WAIT_START,
		MODE_START_TIMING,
		MODE_START_HOLD,
		MODE_RUN,
		MODE_WAIT_ACTIVE_VBLANK,
		MODE_WAIT_TIMING_WRAP,
		MODE_WAIT_TARGET_VBLANK,
		MODE_HOLD_TARGET_FRAME
	} mode_state_t;

	mode_state_t mode_state = MODE_WAIT_START;
	mode_key_t key_active_q = '{12'd480, 1'b0, 1'b0};
	mode_key_t key_pending_q = '{12'd480, 1'b0, 1'b0};
	video_mode_t mode_q = decode_video_mode(12'd480, 1'b0, 1'b0);
	video_mode_t pending_mode_q = decode_video_mode(12'd480, 1'b0, 1'b0);
	logic mode_ready = 1'b0;
	logic video_mode_toggle_q = 1'b0;
	logic video_freeze_q = 1'b1;
	logic active_bypass_q = 1'b0;
	logic pending_bypass_q = 1'b0;
	logic transition_timing_q = 1'b0;
	logic transition_restart_q = 1'b0;
	logic mode_restart_q = 1'b0;
	logic frame_wrap;
	logic raw_path_vblank;
	logic processed_path_vblank;
	logic raw_path_vblank_q = 1'b1;
	logic processed_path_vblank_q = 1'b1;
	logic output_vblank_q = 1'b1;
	logic output_vblank_entry_q = 1'b0;

	wire raw_path_vblank_entry = raw_path_vblank && !raw_path_vblank_q;
	wire processed_path_vblank_entry =
		processed_path_vblank && !processed_path_vblank_q;
	wire progressive_active_vblank_entry = active_bypass_q ?
		raw_path_vblank_entry : processed_path_vblank_entry;
	wire progressive_target_vblank_entry = pending_bypass_q ?
		raw_path_vblank_entry : processed_path_vblank_entry;
	wire active_path_vblank_entry = key_active_q.interlaced ?
		output_vblank_entry_q : progressive_active_vblank_entry;
	wire target_path_vblank_entry = key_pending_q.interlaced ?
		output_vblank_entry_q : progressive_target_vblank_entry;
	wire request_changed = (request_key != key_active_q) ||
	                       (request_bypass != active_bypass_q);
	wire profile_path_commit =
		(mode_state == MODE_WAIT_TARGET_VBLANK) &&
		!transition_restart_q && target_path_vblank_entry &&
		(pending_bypass_q != active_bypass_q);
	wire mode_commit = (mode_state == MODE_WAIT_TIMING_WRAP) && frame_wrap;
	wire timing_reset = !mode_ready;
	logic [1:0] renderer_reset_sync = 2'b11;
	always_ff @(posedge clk_125)
		renderer_reset_sync <= {
			renderer_reset_sync[0], reset || !mode_ready || mode_restart_q
		};
	wire renderer_reset = renderer_reset_sync[1];

	assign video_mode_toggle = video_mode_toggle_q;
	assign video_freeze = video_freeze_q;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || !mode_ready) begin
			raw_path_vblank_q <= 1'b1;
			processed_path_vblank_q <= 1'b1;
			output_vblank_q <= 1'b1;
			output_vblank_entry_q <= 1'b0;
		end else begin
			raw_path_vblank_q <= raw_path_vblank;
			processed_path_vblank_q <= processed_path_vblank;
			output_vblank_entry_q <= ce_pixel && vblank && !output_vblank_q;
			if (ce_pixel)
				output_vblank_q <= vblank;
		end
	end

	always_ff @(posedge clk_125) begin
		if (upload_reset_125) begin
			key_active_q <= '{12'd480, 1'b0, 1'b0};
			key_pending_q <= '{12'd480, 1'b0, 1'b0};
			mode_q <= decode_video_mode(12'd480, 1'b0, 1'b0);
			pending_mode_q <= decode_video_mode(12'd480, 1'b0, 1'b0);
			active_bypass_q <= 1'b0;
			pending_bypass_q <= 1'b0;
			transition_timing_q <= 1'b0;
			transition_restart_q <= 1'b0;
			mode_restart_q <= 1'b0;
			mode_state <= MODE_WAIT_START;
			mode_ready <= 1'b0;
			video_mode_toggle_q <= 1'b0;
			video_freeze_q <= 1'b1;
		end else begin
			case (mode_state)
				MODE_WAIT_START: begin
					mode_ready <= 1'b0;
					video_freeze_q <= 1'b1;
					mode_restart_q <= 1'b0;
					if (request_valid) begin
						key_active_q <= request_key;
						key_pending_q <= request_key;
						mode_q <= requested_mode;
						pending_mode_q <= requested_mode;
						active_bypass_q <= request_bypass;
						pending_bypass_q <= request_bypass;
						mode_state <= MODE_START_TIMING;
					end
				end

				MODE_START_TIMING: begin
					mode_ready <= 1'b1;
					video_freeze_q <= 1'b1;
					mode_state <= MODE_START_HOLD;
				end

				MODE_START_HOLD: begin
					if (frame_wrap) begin
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end
				end

				MODE_RUN: begin
					video_freeze_q <= 1'b0;
					mode_restart_q <= 1'b0;
					transition_restart_q <= 1'b0;
					if (request_valid && request_changed) begin
						key_pending_q <= request_key;
						pending_mode_q <= requested_mode;
						pending_bypass_q <= request_bypass;
						mode_state <= MODE_WAIT_ACTIVE_VBLANK;
					end
				end

				MODE_WAIT_ACTIVE_VBLANK: begin
					if (request_valid && !request_changed) begin
						mode_state <= MODE_RUN;
					end else if (request_valid) begin
						key_pending_q <= request_key;
						pending_mode_q <= requested_mode;
						pending_bypass_q <= request_bypass;
						if (active_path_vblank_entry) begin
							transition_timing_q <= request_key != key_active_q;
							transition_restart_q <=
								height_class(request_key.height) !=
								height_class(key_active_q.height);
							video_freeze_q <= 1'b1;
							mode_state <= (request_key != key_active_q) ?
								MODE_WAIT_TIMING_WRAP : MODE_WAIT_TARGET_VBLANK;
						end
					end
				end

				MODE_WAIT_TIMING_WRAP: begin
					video_freeze_q <= 1'b1;
					if (frame_wrap) begin
						key_active_q <= key_pending_q;
						mode_q <= pending_mode_q;
						video_mode_toggle_q <= !video_mode_toggle_q;
						mode_restart_q <= transition_restart_q;
						mode_state <= MODE_WAIT_TARGET_VBLANK;
					end
				end

				MODE_WAIT_TARGET_VBLANK: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						mode_restart_q <= 1'b0;
						active_bypass_q <= pending_bypass_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end else if (!transition_restart_q &&
					             target_path_vblank_entry) begin
						active_bypass_q <= pending_bypass_q;
						if (!transition_timing_q)
							video_mode_toggle_q <= !video_mode_toggle_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end
				end

				MODE_HOLD_TARGET_FRAME: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						transition_restart_q <= 1'b0;
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end else if (!transition_restart_q &&
					             target_path_vblank_entry) begin
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end
				end

				default: mode_state <= MODE_WAIT_START;
			endcase
		end
	end

	wire [11:0] fb_width = mode_q.fb_width;
	wire [11:0] fb_height = mode_q.fb_height;
	wire [11:0] x_center = mode_q.center_x;
	wire [11:0] y_center = mode_q.center_y;
	wire  [5:0] scale_num = effective_swap ?
		mode_q.scale_swapped : mode_q.scale_normal;
	wire [12:0] optimized_arx = mode_q.optimized_arx;
	wire [12:0] optimized_ary = mode_q.optimized_ary;
	wire is_240p = mode_q.is_240p;
	wire is_120hz = mode_q.is_120hz;

	logic half_rate_phase = 1'b0;
	logic [17:0] fractional_phase = 18'd0;
	logic [10:0] h_counter = 11'd0;
	logic [10:0] v_counter = 11'd0;
	logic progressive_ce_pixel = 1'b0;
	logic v_end_q = 1'b0;
	logic raw_hsync;
	logic raw_vsync;
	logic raw_hblank;
	logic raw_vblank;

	wire h_end = h_counter >= mode_q.h_total[10:0];
	wire v_end = v_end_q;
	assign frame_wrap = progressive_ce_pixel && h_end && v_end;

	always_ff @(posedge clk_125) begin
		if (timing_reset || mode_commit)
			v_end_q <= 1'b0;
		else
			v_end_q <= v_counter >= mode_q.v_total[10:0];
	end

	always_ff @(posedge clk_125) begin
		if (timing_reset) begin
			half_rate_phase <= 1'b0;
			fractional_phase <= 18'd0;
			h_counter <= mode_q.h_total[10:0];
			v_counter <= mode_q.fb_height[10:0] + 11'd2;
			progressive_ce_pixel <= 1'b0;
		end else if (mode_commit) begin
			half_rate_phase <= 1'b0;
			fractional_phase <= 18'd0;
			h_counter <= 11'd0;
			v_counter <= 11'd0;
			progressive_ce_pixel <= 1'b0;
		end else begin
			half_rate_phase <= !half_rate_phase;
			case (mode_q.pixel_mode)
				PIXEL_FULL: progressive_ce_pixel <= 1'b1;
				PIXEL_HALF: progressive_ce_pixel <= !half_rate_phase;
				default: begin
					if (fractional_phase >= mode_q.pixel_wrap) begin
						fractional_phase <= fractional_phase -
						                    mode_q.pixel_wrap;
						progressive_ce_pixel <= 1'b1;
					end else begin
						fractional_phase <= fractional_phase +
						                    mode_q.pixel_step;
						progressive_ce_pixel <= 1'b0;
					end
				end
			endcase

			if (progressive_ce_pixel) begin
				if (h_end) begin
					h_counter <= 11'd0;
					v_counter <= v_end ? 11'd0 : v_counter + 1'd1;
				end else begin
					h_counter <= h_counter + 1'd1;
				end
			end
		end
	end

	always_comb begin
		raw_hsync = !((h_counter >= mode_q.hs_start[10:0]) &&
		              (h_counter < mode_q.hs_end[10:0]));
		raw_vsync = !((v_counter >= mode_q.vs_start[10:0]) &&
		              (v_counter < mode_q.vs_end[10:0]));
		raw_hblank = h_counter >= mode_q.fb_width[10:0];
		raw_vblank = v_counter >= mode_q.fb_height[10:0];
	end

	always_comb begin
		case (aspect_ratio)
			2'd0: begin video_arx = optimized_arx; video_ary = optimized_ary; end
			2'd1: begin video_arx = 13'd0;         video_ary = 13'd0;         end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	assign mode_supports_120hz = mode_ready && height_supports_120hz;
	assign mode_is_15khz = mode_ready &&
	                       (is_240p || mode_q.is_interlaced);

	logic [2:0] effective_dot_mode;
	logic [1:0] effective_tone_mapping;
	logic [2:0] effective_bloom_width;
	logic [2:0] effective_bloom_curve;
	logic [2:0] effective_halo_filter;
	logic [2:0] effective_halo_curve;
	logic [1:0] effective_halo_spread;
	logic [1:0] effective_halo_knee;
	logic [1:0] effective_inter_frame_decay;
	logic [1:0] effective_intra_frame_decay;
	logic       effective_color_space;
	logic [2:0] effective_presentation_color;
	logic       effective_slot_mask;

	vfb_profile_resolver profile_resolver (
		.profile(profile),
		.fb_height(fb_height),
		.off_dot_mode(3'd3),
		.off_tonemapping(2'd3),
		.off_inter_frame_decay(2'd0),
		.off_intra_frame_decay(2'd0),
		.custom1_settings(custom_1_settings),
		.custom2_settings(custom_2_settings),
		.dot_mode(effective_dot_mode),
		.tonemapping(effective_tone_mapping),
		.bloom_width(effective_bloom_width),
		.bloom_curve(effective_bloom_curve),
		.halo_filter(effective_halo_filter),
		.halo_curve(effective_halo_curve),
		.halo_spread(effective_halo_spread),
		.halo_knee(effective_halo_knee),
		.inter_frame_decay(effective_inter_frame_decay),
		.intra_frame_decay(effective_intra_frame_decay),
		.color_space(effective_color_space),
		.presentation_color(effective_presentation_color),
		.slot_mask(effective_slot_mask),
		.full_bypass()
	);

	// ------------------------------------------------------------------
	// Coordinate map
	// ------------------------------------------------------------------
	wire [61:0] geometry_control_in = {
		fb_width, fb_height, x_center, y_center, scale_num,
		is_240p, stable_game_orientation, stable_screen_rotation, open_matte
	};
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [61:0] geometry_control_meta = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [61:0] geometry_control_sync = '0;
	logic [61:0] geometry_control_sync_d = '0;
	logic [61:0] geometry_control_stable = '0;

	always_ff @(posedge clk_master) begin
		geometry_control_meta <= geometry_control_in;
		geometry_control_sync <= geometry_control_meta;
		geometry_control_sync_d <= geometry_control_sync;
		if (geometry_control_sync == geometry_control_sync_d)
			geometry_control_stable <= geometry_control_sync;
	end

	wire [11:0] geometry_width = geometry_control_stable[61:50];
	wire [11:0] geometry_height = geometry_control_stable[49:38];
	wire [11:0] geometry_center_x = geometry_control_stable[37:26];
	wire [11:0] geometry_center_y = geometry_control_stable[25:14];
	wire  [5:0] geometry_scale = geometry_control_stable[13:8];
	wire        geometry_240p = geometry_control_stable[7];
	wire  [2:0] geometry_game_orientation = geometry_control_stable[6:4];
	wire  [1:0] geometry_screen_rotation = geometry_control_stable[3:2];
	wire  [1:0] geometry_open_matte = geometry_control_stable[1:0];

	wire [10:0] rast_x, rast_y;
	wire        rast_in_bounds;

	sega_geometry geom (
		.src_x         (vec_x),
		.src_y         (vec_y),
		.game_orientation(geometry_game_orientation),
		.screen_rotation(geometry_screen_rotation),
		.open_matte    (geometry_open_matte),
		.mode_240p     (geometry_240p),
		.scale_num     (geometry_scale),
		.center_x      (geometry_center_x),
		.center_y      (geometry_center_y),
		.render_width  (geometry_width),
		.render_height (geometry_height),
		.raster_x      (rast_x),
		.raster_y      (rast_y),
		.in_bounds     (rast_in_bounds)
	);

	// Latch each valid vector sample. Preserve frame_done for the rasterizer's
	// source-domain edge detector.
	logic [10:0] fb_x, fb_y;
	logic  [5:0] fb_c;
	logic        fb_beam, fb_frame_done;

	always_ff @(posedge clk_master) begin
		if (reset_source) begin
			fb_x <= 11'd0; fb_y <= 11'd0; fb_c <= 6'd0;
			fb_beam <= 1'b0; fb_frame_done <= 1'b0;
		end else begin
			fb_frame_done <= frame_done;
			if (vec_valid) begin
				fb_x    <= rast_x;
				fb_y    <= rast_y;
				fb_c    <= vec_colour;
				fb_beam <= vec_beam && rast_in_bounds;
			end else begin
				fb_beam <= 1'b0;
			end
		end
	end

	wire [7:0] progressive_video_r;
	wire [7:0] progressive_video_g;
	wire [7:0] progressive_video_b;
	wire progressive_hsync;
	wire progressive_vsync;
	wire progressive_hblank;
	wire progressive_vblank;

	vfb_top renderer (
		.clk_sys             (clk_125),
		.clk_source          (clk_master),
		.source_tick         (vec_tick),
		.reset               (renderer_reset),
		.video_timing_reset  (timing_reset),

		.X_VECTOR            (fb_x),
		.Y_VECTOR            (fb_y),
		.COLOR               (fb_c),
		.IS_DOT              (1'b0),
		.BEAM_ON             (fb_beam),

		.DDRAM_CLK           (ddram_clk),
		.DDRAM_BUSY          (ddram_busy),
		.DDRAM_BURSTCNT      (ddram_burst_count),
		.DDRAM_ADDR          (ddram_address),
		.DDRAM_DOUT          (ddram_data_out),
		.DDRAM_DOUT_READY    (ddram_data_ready),
		.DDRAM_RD            (ddram_read),
		.DDRAM_DIN           (ddram_data_in),
		.DDRAM_BE            (ddram_byte_enable),
		.DDRAM_WE            (ddram_write),

		.SDRAM_DQ_IN         (sdram_data_in),
		.SDRAM_DQ_OUT        (sdram_data_out),
		.SDRAM_DQ_OE         (sdram_data_oe),
		.SDRAM_CKE           (sdram_cke),
		.SDRAM_nCS           (sdram_ncs),
		.SDRAM_nRAS          (sdram_nras),
		.SDRAM_nCAS          (sdram_ncas),
		.SDRAM_nWE           (sdram_nwe),
		.SDRAM_DQM           (sdram_dqm),
		.SDRAM_A             (sdram_address),
		.SDRAM_BA            (sdram_bank),

		.RENDER_WIDTH        (fb_width),
		.RENDER_HEIGHT       (fb_height),

		.VGA_R               (progressive_video_r),
		.VGA_G               (progressive_video_g),
		.VGA_B               (progressive_video_b),
		.VGA_HS              (progressive_hsync),
		.VGA_VS              (progressive_vsync),
		.VGA_HBLANK          (progressive_hblank),
		.VGA_VBLANK          (progressive_vblank),

		.h_cnt               (h_counter),
		.v_cnt               (v_counter),
		.ce_pix              (progressive_ce_pixel),
		.hsync               (raw_hsync),
		.vsync               (raw_vsync),
		.hblank              (raw_hblank),
		.vblank              (raw_vblank),

		.FLASH_PARAM         (osd_flash_param),
		.OSD_120HZ           (is_120hz),
		.FRAME_DONE          (fb_frame_done),
		.FRAME_START         (frame_start),
		.BUFFER_MODE         (osd_buffer_mode),
		.DOT_MODE            (effective_dot_mode),
		.FIFO_FULL_LED       (fifo_full),

		.osd_bloom_width     (effective_bloom_width),
		.osd_bloom_curve     (effective_bloom_curve),
		.osd_halo_filter     (effective_halo_filter),
		.osd_phosphor_mode   (effective_intra_frame_decay),
		.osd_inter_frame_phosphor_mode (effective_inter_frame_decay),
		.osd_halo_spread     (effective_halo_spread),
		.osd_halo_curve      (effective_halo_curve),
		.osd_halo_knee       (effective_halo_knee),
		.osd_tone_mapping     (effective_tone_mapping),
		.osd_color_space     (effective_color_space),
		.osd_presentation_color(effective_presentation_color),
		.osd_slot_mask       (effective_slot_mask),
		.osd_slot_mask_rows  (effective_swap),
		.full_bypass_active  (active_bypass_q),
		.raw_path_vblank     (raw_path_vblank),
		.processed_path_vblank(processed_path_vblank)
	);

	localparam logic [1:0] INTERLACER_PATH_RESTART_CYCLES = 2'd3;
	logic [1:0] interlacer_restart_count = 2'd0;
	logic interlacer_mode_commit_q = 1'b0;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset)
			interlacer_mode_commit_q <= 1'b0;
		else
			interlacer_mode_commit_q <= mode_commit;
	end

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset || !mode_q.is_interlaced)
			interlacer_restart_count <= 2'd0;
		else if (profile_path_commit)
			interlacer_restart_count <= INTERLACER_PATH_RESTART_CYCLES;
		else if (interlacer_restart_count != 2'd0)
			interlacer_restart_count <= interlacer_restart_count - 1'd1;
	end

	vfb_interlacer interlacer (
		.clk_sys(clk_125),
		.reset(timing_reset || interlacer_mode_commit_q ||
		       mode_restart_q || !mode_q.is_interlaced ||
		       (interlacer_restart_count != 2'd0)),
		.enable(mode_q.is_interlaced),
		.ce_pix_in(progressive_ce_pixel),
		.r_in(progressive_video_r),
		.g_in(progressive_video_g),
		.b_in(progressive_video_b),
		.hsync_in(progressive_hsync),
		.vsync_in(progressive_vsync),
		.hblank_in(progressive_hblank),
		.vblank_in(progressive_vblank),
		.ce_pix_out(ce_pixel),
		.r_out(video_r),
		.g_out(video_g),
		.b_out(video_b),
		.hsync_out(hsync),
		.vsync_out(vsync),
		.hblank_out(hblank),
		.vblank_out(vblank),
		.field_out(field)
	);

endmodule

`default_nettype wire
