// ============================================================================
// Framebuffer readout and phosphor-decay stage.
// Written 2026 by Videodr0me
// Operates in the renderer/video clock domain.
// Reads tile rows from DDRAM, converts them back to pixels, and applies
// phosphor decay and the hit-flash background.
// ============================================================================

module vfb_readout #(
	parameter TILE_SIZE = 8,
	parameter MAX_BURST_TILES = 15
) (
	input  logic clk_sys,
	input  logic reset,

	// DDRAM read interface
	output logic        readout_ready,
	input  logic        readout_grant,
	output logic [15:0] readout_tile_id,
	output logic [8:0]  readout_burstcnt,
	input  logic [63:0] readout_data,
	input  logic        readout_data_valid,

	output logic        vbl_swap_req,

	// Video output
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic [12:0] CANONICAL_PIXEL,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  logic [10:0] h_cnt,
	input  logic [10:0] v_cnt,
	input  logic        ce_pix,
	input  logic        hsync,
	input  logic        vsync,
	input  logic        hblank,
	input  logic        vblank,

	input  logic [23:0] FLASH_PARAM,
	input  logic [11:0] RENDER_WIDTH,
	input  logic [11:0] RENDER_HEIGHT,

	input  logic [2:0]  draw_idx,           // Phosphor persistence draw index
	input  logic [31:0] phosphor_age_map,   // Eight packed physical-age entries
	input  logic [1:0]  osd_phosphor_mode,  // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  logic [1:0]  tone_mapping,
	input  logic        display_is_composed,

	output logic [14:0] display_tile_addr,
	input  logic        display_tile_dirty
);

	import vfb_layout_pkg::*;

	// Two row buffers support up to 184 tile columns plus one guard tile.
	// Each row is split between 2K and 1K banks.
	localparam ROW_TILES = 185;
	localparam ROW_LOW_WORDS = 2048;
	localparam ROW_HIGH_WORDS = 1024;

	logic [1:0] phosphor_mode_control_q = 2'd0;
	logic [1:0] tone_mapping_control_q = 2'd3;
	logic [11:0] render_width_q = 12'd720;
	logic [11:0] render_height_q = 12'd480;
	always_ff @(posedge clk_sys) begin
		phosphor_mode_control_q <= osd_phosphor_mode;
		tone_mapping_control_q <= tone_mapping;
		render_width_q <= RENDER_WIDTH;
		render_height_q <= RENDER_HEIGHT;
	end

	(* ramstyle = "M10K" *) logic [63:0] buffer_0_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_0_high [0:ROW_HIGH_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_high [0:ROW_HIGH_WORDS-1];

	logic buf_state;

	// Register timing before tile addressing and edge detection.
	logic [10:0] h_cnt_r, v_cnt_r;
	logic        hsync_r, vsync_r, hblank_r, vblank_r;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			// Restart edge detection from blanking.
			h_cnt_r  <= 0;
			v_cnt_r  <= 0;
			hsync_r  <= 0;
			vsync_r  <= 0;
			hblank_r <= 1;
			vblank_r <= 1;
		end else begin
			h_cnt_r  <= h_cnt;
			v_cnt_r  <= v_cnt;
			hsync_r  <= hsync;
			vsync_r  <= vsync;
			hblank_r <= hblank;
			vblank_r <= vblank;
		end
	end

	// Detect line and VBLANK edges.
	logic [10:0] prev_h_cnt;
	logic        prev_hblank_r;
	logic start_prefetch_row0;
	logic advance_row;
	logic [7:0] advance_fetch_y;

	typedef enum logic [2:0] {
		IDLE,
		SCAN_WAIT,
		SCAN_CAPTURE,
		SCAN_DECIDE,
		ZERO_DATA,
		BURST_REQ,
		BURST_WAIT,
		BURST_DATA
	} fetch_state_t;
	fetch_state_t fetch_state = IDLE;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			prev_h_cnt <= 0;
			prev_hblank_r <= 1;
			start_prefetch_row0 <= 0;
			advance_row <= 0;
			advance_fetch_y <= 0;
			vbl_swap_req <= 0;
		end else begin
			prev_h_cnt <= h_cnt_r;
			prev_hblank_r <= hblank_r;

			start_prefetch_row0 <= 0;
			advance_row <= 0;
			vbl_swap_req <= 0;

			// Start a new output line.
			if (h_cnt_r == 0 && prev_h_cnt != 0) begin
				if (v_cnt_r == render_height_q) begin
					// VBLANK starts: prepare row 0.
					start_prefetch_row0 <= 1;
					vbl_swap_req <= 1;
				end
			end

			// Switch rows during blanking after local line 7.
			if (!prev_hblank_r && hblank_r) begin
				if ((v_cnt_r + 11'd1) < render_height_q &&
				    v_cnt_r[2:0] == 3'd7) begin
					if (fetch_state == IDLE) begin
						advance_row <= 1;
						advance_fetch_y <= v_cnt_r[10:3] + 8'd2;
					end
				end
			end
		end
	end

	// Fill the row buffers.

	// Tile-grid dimensions change only with the video mode.
	logic [8:0] render_tile_cols;  // ceil(RENDER_WIDTH / 8)
	logic [8:0] render_tile_rows;  // ceil(RENDER_HEIGHT / 8)
	always_ff @(posedge clk_sys) begin
		render_tile_cols <= vfb_tile_columns(render_width_q);
		render_tile_rows <= vfb_tile_rows(render_height_q);
	end

	logic [7:0] fetch_tile_x;
	logic [7:0] target_fetch_y;
	logic [14:0] fetch_tile_addr;
	logic       row0_prefetch_active;
	logic       scan_tile_dirty = 1'b0;

	logic [7:0] run_start_x;
	logic [4:0] run_length;     // Dirty tiles in the pending burst
	logic [4:0] zero_word_cnt;  // 0 to 15 for inline zeroing
	logic [8:0] burst_beat_cnt; // Accepted beats in the active burst

	assign display_tile_addr = fetch_tile_addr;

	wire row_end = ({4'd0, fetch_tile_x} + 12'd1 >= {3'd0, render_tile_cols});
	wire row_done = ({4'd0, fetch_tile_x} >= {3'd0, render_tile_cols});

	// Row-buffer write pipeline
	logic        bram_we_r;
	logic        bram_buf_r;
	logic [11:0] bram_addr_r;
	logic [63:0] bram_data_r;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			fetch_state <= IDLE;
			readout_ready <= 0;
			buf_state <= 0;
			bram_we_r <= 0;
			fetch_tile_addr <= 0;
			row0_prefetch_active <= 0;
		end else begin
			// At VBLANK, abandon an incomplete fetch and restart at row 0.
			if (start_prefetch_row0) begin
				buf_state <= 0; // Reset rolling buffer
				target_fetch_y <= 0;
				fetch_tile_x <= 0;
				fetch_tile_addr <= 0;
				run_length <= 0;
				fetch_state <= SCAN_WAIT;
				readout_ready <= 0; // Cancel any pending request.
				row0_prefetch_active <= 1;
			end else begin
				case (fetch_state)
					IDLE: begin
						if (advance_row) begin
							buf_state <= ~buf_state;
							target_fetch_y <= advance_fetch_y;
							// Fetch only if the following row is visible.
							if ({1'b0, advance_fetch_y} < render_tile_rows) begin
								fetch_tile_x <= 0;
								fetch_tile_addr <=
									vfb_tile_row_addr(advance_fetch_y);
								run_length <= 0;
								fetch_state <= SCAN_WAIT;
							end
						end
					end

				SCAN_WAIT: begin
					// Wait one cycle for the synchronous tilemap query.
					fetch_state <= SCAN_CAPTURE;
				end

				SCAN_CAPTURE: begin
					scan_tile_dirty <= display_tile_dirty;
					fetch_state <= SCAN_DECIDE;
				end

				SCAN_DECIDE: begin
					if (scan_tile_dirty) begin
						if (run_length == 0) run_start_x <= fetch_tile_x;

						if (row_end) begin
							// End of row: request the run including this tile.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= BURST_REQ;
						end else if (run_length + 5'd1 == MAX_BURST_TILES[4:0]) begin
							// The run reached its burst limit.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= BURST_REQ;
						end else begin
							// Continue along the row.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= SCAN_WAIT;
						end
					end else begin
						if (run_length > 0) begin
							// Request the dirty run before checking this clean tile.
							fetch_state <= BURST_REQ;
						end else begin
							// No dirty run: clear this tile locally.
							zero_word_cnt <= 0;
							fetch_state <= ZERO_DATA;
						end
					end
				end

				ZERO_DATA: begin
					if (zero_word_cnt == 5'd15) begin
						if (row_end) begin
							if (row0_prefetch_active) begin
								row0_prefetch_active <= 0;
								buf_state <= ~buf_state;
								target_fetch_y <= 8'd1;
								if (render_tile_rows > 9'd1) begin
									fetch_tile_x <= 0;
									fetch_tile_addr <=
										vfb_tile_row_addr(8'd1);
									run_length <= 0;
									fetch_state <= SCAN_WAIT;
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= IDLE;
							end
						end else begin
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= SCAN_WAIT;
						end
					end else begin
						zero_word_cnt <= zero_word_cnt + 5'd1;
					end
				end

				BURST_REQ: begin
					readout_ready <= 1;
					readout_tile_id <= {target_fetch_y, run_start_x};
					readout_burstcnt <= {4'd0, run_length} << 4; // run_length * 16
					burst_beat_cnt <= 0;
					fetch_state <= BURST_WAIT;
				end

				BURST_WAIT: begin
					if (readout_grant) begin
						readout_ready <= 0;
						fetch_state <= BURST_DATA;
					end
				end

				BURST_DATA: begin
					if (readout_data_valid) begin
						if (burst_beat_cnt + 9'd1 == readout_burstcnt) begin
							run_length <= 0;
							if (row_done) begin
								if (row0_prefetch_active) begin
									row0_prefetch_active <= 0;
									buf_state <= ~buf_state;
									target_fetch_y <= 8'd1;
									if (render_tile_rows > 9'd1) begin
										fetch_tile_x <= 0;
										fetch_tile_addr <=
											vfb_tile_row_addr(8'd1);
										run_length <= 0;
										fetch_state <= SCAN_WAIT;
									end else begin
										fetch_state <= IDLE;
									end
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= SCAN_WAIT;
							end
						end else begin
							burst_beat_cnt <= burst_beat_cnt + 9'd1;
						end
					end
				end
				endcase
			end

			// Write the prepared row-buffer word.
			bram_we_r <= 0;
			if (fetch_state == BURST_DATA && readout_data_valid) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {run_start_x + burst_beat_cnt[8:4], burst_beat_cnt[3:0]};
				bram_data_r <= readout_data;
			end else if (fetch_state == ZERO_DATA) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {fetch_tile_x, zero_word_cnt[3:0]};
				bram_data_r <= 64'd0;
			end

			if (bram_we_r) begin
				if (bram_buf_r == 0) begin
					if (!bram_addr_r[11])
						buffer_0_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_0_high[bram_addr_r[9:0]] <= bram_data_r;
				end else begin
					if (!bram_addr_r[11])
						buffer_1_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_1_high[bram_addr_r[9:0]] <= bram_data_r;
				end
			end
		end
	end

	// Convert tile words back to pixels. Sync and blanking follow the same
	// row-read, decay, and five-stage Sega color path.
	localparam READ_ADVANCE = 11;

	logic [READ_ADVANCE-1:0] hs_pipe, vs_pipe, hb_pipe, vb_pipe;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hs_pipe <= {READ_ADVANCE{1'b1}};
			vs_pipe <= {READ_ADVANCE{1'b1}};
			hb_pipe <= {READ_ADVANCE{1'b1}};
			vb_pipe <= {READ_ADVANCE{1'b1}};
		end else if (ce_pix) begin
			hs_pipe <= {hs_pipe[READ_ADVANCE-2:0], hsync_r};
			vs_pipe <= {vs_pipe[READ_ADVANCE-2:0], vsync_r};
			hb_pipe <= {hb_pipe[READ_ADVANCE-2:0], hblank_r};
			vb_pipe <= {vb_pipe[READ_ADVANCE-2:0], vblank_r};
		end
	end

	wire vga_hs_pre     = hs_pipe[READ_ADVANCE-2];
	wire vga_vs_pre     = vs_pipe[READ_ADVANCE-2];
	wire vga_hblank_pre = hb_pipe[READ_ADVANCE-2];
	wire vga_vblank_pre = vb_pipe[READ_ADVANCE-2];

	// Pixel read addresses
	wire [7:0] cur_tile_x = h_cnt_r[10:3];
	wire [5:0] cur_offset = {v_cnt_r[2:0], h_cnt_r[2:0]};
	wire [7:0] safe_tile_x =
		(hblank_r || cur_tile_x >= ROW_TILES) ? 8'(ROW_TILES-1) : cur_tile_x;
	wire [13:0] read_addr = {safe_tile_x, cur_offset}; // [13:2] = word addr, [1:0] = pixel sel
	wire [11:0] read_word_addr = read_addr[13:2];
	logic [1:0] pixel_sel_d1;
	logic [1:0] pixel_sel_d2;
	logic       buf_state_d1;
	logic       word_bank_d1;
	logic [63:0] raw_word_0_low, raw_word_0_high;
	logic [63:0] raw_word_1_low, raw_word_1_high;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d1 <= read_addr[1:0];
			buf_state_d1 <= buf_state;
			word_bank_d1 <= read_word_addr[11];
			raw_word_0_low <= buffer_0_low[read_word_addr[10:0]];
			raw_word_0_high <= buffer_0_high[read_word_addr[9:0]];
			raw_word_1_low <= buffer_1_low[read_word_addr[10:0]];
			raw_word_1_high <= buffer_1_high[read_word_addr[9:0]];
		end
	end

	logic [63:0] raw_word;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d2 <= pixel_sel_d1;
			case ({buf_state_d1, word_bank_d1})
				2'b00: raw_word <= raw_word_0_low;
				2'b01: raw_word <= raw_word_0_high;
				2'b10: raw_word <= raw_word_1_low;
				2'b11: raw_word <= raw_word_1_high;
			endcase
		end
	end

	logic [15:0] raw_pixel;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			case (pixel_sel_d2)
				2'b00: raw_pixel <= raw_word[15:0];
				2'b01: raw_pixel <= raw_word[31:16];
				2'b10: raw_pixel <= raw_word[47:32];
				2'b11: raw_pixel <= raw_word[63:48];
			endcase
		end
	end

	// Phosphor decay and RGB conversion

	// Raw and composed pixels share their color and intensity positions.
	wire [5:0] pixel_color_comb = vfb_pixel_color(raw_pixel);
	wire [6:0] pixel_int_comb = vfb_pixel_intensity(raw_pixel);

	// Approximate 8-bit exponential factors for bases 0.94, 0.96, and 0.98.
	function automatic logic [7:0] decay_factor(
		input logic [1:0] mode,
		input logic [3:0] age
	);
		case ({mode, age})
			// LUT A (mode 1, base 0.94)
			{2'd1, 4'd0}:  decay_factor = 8'd255;
			{2'd1, 4'd1}:  decay_factor = 8'd240;
			{2'd1, 4'd2}:  decay_factor = 8'd225;
			{2'd1, 4'd3}:  decay_factor = 8'd212;
			{2'd1, 4'd4}:  decay_factor = 8'd199;
			{2'd1, 4'd5}:  decay_factor = 8'd187;
			{2'd1, 4'd6}:  decay_factor = 8'd176;
			{2'd1, 4'd7}:  decay_factor = 8'd165;
			{2'd1, 4'd8}:  decay_factor = 8'd155;
			{2'd1, 4'd9}:  decay_factor = 8'd146;
			{2'd1, 4'd10}: decay_factor = 8'd137;
			{2'd1, 4'd11}: decay_factor = 8'd129;
			{2'd1, 4'd12}: decay_factor = 8'd121;
			{2'd1, 4'd13}: decay_factor = 8'd114;
			{2'd1, 4'd14}: decay_factor = 8'd107;
			{2'd1, 4'd15}: decay_factor = 8'd101;
			// LUT B (mode 2, base 0.96)
			{2'd2, 4'd0}:  decay_factor = 8'd255;
			{2'd2, 4'd1}:  decay_factor = 8'd245;
			{2'd2, 4'd2}:  decay_factor = 8'd235;
			{2'd2, 4'd3}:  decay_factor = 8'd226;
			{2'd2, 4'd4}:  decay_factor = 8'd217;
			{2'd2, 4'd5}:  decay_factor = 8'd208;
			{2'd2, 4'd6}:  decay_factor = 8'd200;
			{2'd2, 4'd7}:  decay_factor = 8'd192;
			{2'd2, 4'd8}:  decay_factor = 8'd184;
			{2'd2, 4'd9}:  decay_factor = 8'd177;
			{2'd2, 4'd10}: decay_factor = 8'd170;
			{2'd2, 4'd11}: decay_factor = 8'd163;
			{2'd2, 4'd12}: decay_factor = 8'd156;
			{2'd2, 4'd13}: decay_factor = 8'd150;
			{2'd2, 4'd14}: decay_factor = 8'd144;
			{2'd2, 4'd15}: decay_factor = 8'd138;
			// LUT C (mode 3, base 0.98)
			{2'd3, 4'd0}:  decay_factor = 8'd255;
			{2'd3, 4'd1}:  decay_factor = 8'd250;
			{2'd3, 4'd2}:  decay_factor = 8'd245;
			{2'd3, 4'd3}:  decay_factor = 8'd240;
			{2'd3, 4'd4}:  decay_factor = 8'd235;
			{2'd3, 4'd5}:  decay_factor = 8'd230;
			{2'd3, 4'd6}:  decay_factor = 8'd225;
			{2'd3, 4'd7}:  decay_factor = 8'd221;
			{2'd3, 4'd8}:  decay_factor = 8'd216;
			{2'd3, 4'd9}:  decay_factor = 8'd212;
			{2'd3, 4'd10}: decay_factor = 8'd208;
			{2'd3, 4'd11}: decay_factor = 8'd204;
			{2'd3, 4'd12}: decay_factor = 8'd200;
			{2'd3, 4'd13}: decay_factor = 8'd196;
			{2'd3, 4'd14}: decay_factor = 8'd192;
			{2'd3, 4'd15}: decay_factor = 8'd188;
			default: decay_factor = 8'd255;
		endcase
	endfunction

	function automatic logic [8:0] mapped_decay_scale(
		input logic [1:0]  mode,
		input logic [2:0]  reference_idx,
		input logic [2:0]  stored_idx,
		input logic [31:0] age_map,
		input logic        composed
	);
		logic [2:0] age_idx;
		logic [3:0] age;
		begin
			age_idx = reference_idx - stored_idx;
			age = age_map[{age_idx, 2'b00} +: 4];
			mapped_decay_scale = (composed || (mode == 2'd0))
				? 9'd256 : {1'b0, decay_factor(mode, age)};
		end
	endfunction

	// Precompute every stored phase so pixels only select a registered scale.
	logic [8:0] decay_scale_map_q [0:7];
	always_ff @(posedge clk_sys) begin
		for (int stored_idx = 0; stored_idx < 8; stored_idx++) begin
			decay_scale_map_q[stored_idx] <= mapped_decay_scale(
				phosphor_mode_control_q, draw_idx, stored_idx[2:0],
				phosphor_age_map, display_is_composed);
		end
	end

	wire [2:0] pixel_draw_idx = vfb_raw_draw_idx(raw_pixel);
	logic [8:0] decay_scale_r;
	logic [6:0] pixel_int_r;
	logic [5:0] pixel_color_r;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			decay_scale_r <= decay_scale_map_q[pixel_draw_idx];
			pixel_int_r    <= pixel_int_comb;
			pixel_color_r  <= pixel_color_comb;
		end
	end

	// Retain the full 7x9-bit product before dividing by 256.
	wire [15:0] scaled_int_full = pixel_int_r * decay_scale_r;

	// Register the canonical post-decay sample.
	logic [6:0] final_int;
	logic [5:0] pixel_color;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			final_int <= scaled_int_full[14:8];
			pixel_color <= pixel_color_r;
		end
	end

	wire [12:0] canonical_in = {pixel_color, final_int};
	wire [12:0] canonical_rgb;
	wire [7:0] color_r;
	wire [7:0] color_g;
	wire [7:0] color_b;

	vfb_sega_color color_converter (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.canonical_in(canonical_in),
		.tone_mapping(tone_mapping_control_q),
		.canonical_out(canonical_rgb),
		.red(color_r),
		.green(color_g),
		.blue(color_b)
	);

	// Register the final output.
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			VGA_R <= 8'd0;
			VGA_G <= 8'd0;
			VGA_B <= 8'd0;
			CANONICAL_PIXEL <= 13'd0;
			VGA_HS <= 1'b1;
			VGA_VS <= 1'b1;
			VGA_HBLANK <= 1'b1;
			VGA_VBLANK <= 1'b1;
		end else if (ce_pix) begin
			VGA_HS <= vga_hs_pre;
			VGA_VS <= vga_vs_pre;
			VGA_HBLANK <= vga_hblank_pre;
			VGA_VBLANK <= vga_vblank_pre;

			if (~vga_hblank_pre && ~vga_vblank_pre) begin
				CANONICAL_PIXEL <= canonical_rgb;
				if (canonical_rgb == 13'd0) begin
					// Flash effect for background pixels.
					VGA_R <= FLASH_PARAM[23:16];
					VGA_G <= FLASH_PARAM[15:8];
					VGA_B <= FLASH_PARAM[7:0];
				end else begin
					VGA_R <= color_r;
					VGA_G <= color_g;
					VGA_B <= color_b;
				end
			end else begin
				VGA_R <= 8'd0;
				VGA_G <= 8'd0;
				VGA_B <= 8'd0;
				CANONICAL_PIXEL <= 13'd0;
			end
		end
	end

endmodule
