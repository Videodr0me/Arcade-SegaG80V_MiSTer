package vfb_layout_pkg;

	localparam integer VFB_BUFFER_COUNT = 5;
	localparam integer VFB_TILE_SIZE = 8;
	localparam integer VFB_TILEMAP_STRIDE = 192;
	localparam logic [15:0] VFB_TILEMAP_ENTRIES_480 = 16'd11520;

	localparam integer VFB_PIXEL_COLOR_MSB = 15;
	localparam integer VFB_PIXEL_COLOR_LSB = 10;
	localparam integer VFB_RAW_DRAW_MSB = 9;
	localparam integer VFB_RAW_DRAW_LSB = 7;
	localparam integer VFB_COMPOSED_FRESH_BIT = 9;
	localparam integer VFB_COMPOSED_RESERVED_MSB = 8;
	localparam integer VFB_COMPOSED_RESERVED_LSB = 7;
	localparam integer VFB_PIXEL_INTENSITY_MSB = 6;
	localparam integer VFB_PIXEL_INTENSITY_LSB = 0;

	localparam integer VFB_SAMPLE_COLOR_MSB = 12;
	localparam integer VFB_SAMPLE_COLOR_LSB = 7;
	localparam integer VFB_SAMPLE_INTENSITY_MSB = 6;
	localparam integer VFB_SAMPLE_INTENSITY_LSB = 0;

	localparam logic [6:0] VFB_BEAM_INTENSITY = 7'd96;
	localparam logic [8:0] VFB_MAX_CHANNEL_ENERGY = 9'd381;

	function automatic logic [28:0] vfb_buffer_base(
		input logic [2:0] index
	);
		begin
			case (index)
				3'd0: vfb_buffer_base = 29'h06000000;
				3'd1: vfb_buffer_base = 29'h06110000;
				3'd2: vfb_buffer_base = 29'h06220000;
				3'd3: vfb_buffer_base = 29'h06330000;
				3'd4: vfb_buffer_base = 29'h06440000;
				default: vfb_buffer_base = 29'h06000000;
			endcase
		end
	endfunction

	function automatic logic [8:0] vfb_tile_columns(
		input logic [11:0] width
	);
		vfb_tile_columns = 9'((width + 12'd7) >> 3);
	endfunction

	function automatic logic [8:0] vfb_tile_rows(
		input logic [11:0] height
	);
		vfb_tile_rows = 9'((height + 12'd7) >> 3);
	endfunction

	function automatic logic [14:0] vfb_tile_row_addr(
		input logic [7:0] tile_y
	);
		logic [15:0] row_base;
		begin
			row_base = ({8'd0, tile_y} << 7)
			         + ({8'd0, tile_y} << 6);
			vfb_tile_row_addr = row_base[14:0];
		end
	endfunction

	function automatic logic [14:0] vfb_linear_tile_addr(
		input logic [15:0] tile_id
	);
		vfb_linear_tile_addr =
			vfb_tile_row_addr(tile_id[15:8]) + {7'd0, tile_id[7:0]};
	endfunction

	function automatic logic [15:0] vfb_tilemap_entries(
		input logic [8:0] rows
	);
		vfb_tilemap_entries =
			({7'd0, rows} << 7) + ({7'd0, rows} << 6);
	endfunction

	function automatic logic [5:0] vfb_pixel_color(
		input logic [15:0] pixel
	);
		vfb_pixel_color =
			pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB];
	endfunction

	function automatic logic [2:0] vfb_raw_draw_idx(
		input logic [15:0] pixel
	);
		vfb_raw_draw_idx = pixel[VFB_RAW_DRAW_MSB:VFB_RAW_DRAW_LSB];
	endfunction

	function automatic logic [6:0] vfb_pixel_intensity(
		input logic [15:0] pixel
	);
		vfb_pixel_intensity =
			pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB];
	endfunction

	function automatic logic vfb_composed_fresh(
		input logic [15:0] pixel
	);
		vfb_composed_fresh = pixel[VFB_COMPOSED_FRESH_BIT];
	endfunction

	function automatic logic [5:0] vfb_sample_color(
		input logic [12:0] sample
	);
		vfb_sample_color =
			sample[VFB_SAMPLE_COLOR_MSB:VFB_SAMPLE_COLOR_LSB];
	endfunction

	function automatic logic [6:0] vfb_sample_intensity(
		input logic [12:0] sample
	);
		vfb_sample_intensity =
			sample[VFB_SAMPLE_INTENSITY_MSB:VFB_SAMPLE_INTENSITY_LSB];
	endfunction

	function automatic logic [15:0] vfb_pack_raw_pixel(
		input logic [5:0] color,
		input logic [2:0] draw_idx,
		input logic [6:0] intensity
	);
		logic [15:0] pixel;
		begin
			pixel = 16'd0;
			if ((color != 6'd0) && (intensity != 7'd0)) begin
				pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB] = color;
				pixel[VFB_RAW_DRAW_MSB:VFB_RAW_DRAW_LSB] = draw_idx;
				pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB]
					= intensity;
			end
			vfb_pack_raw_pixel = pixel;
		end
	endfunction

	function automatic logic [15:0] vfb_pack_composed_pixel(
		input logic [5:0] color,
		input logic       fresh,
		input logic [6:0] intensity
	);
		logic [15:0] pixel;
		begin
			pixel = 16'd0;
			if ((color != 6'd0) && (intensity != 7'd0)) begin
				pixel[VFB_PIXEL_COLOR_MSB:VFB_PIXEL_COLOR_LSB] = color;
				pixel[VFB_COMPOSED_FRESH_BIT] = fresh;
				pixel[VFB_COMPOSED_RESERVED_MSB:
				      VFB_COMPOSED_RESERVED_LSB] = 2'b00;
				pixel[VFB_PIXEL_INTENSITY_MSB:VFB_PIXEL_INTENSITY_LSB]
					= intensity;
			end
			vfb_pack_composed_pixel = pixel;
		end
	endfunction

	function automatic logic [8:0] vfb_channel_energy(
		input logic [1:0] coefficient,
		input logic [6:0] intensity
	);
		logic [8:0] level;
		begin
			level = {2'd0, intensity};
			case (coefficient)
				2'd0: vfb_channel_energy = 9'd0;
				2'd1: vfb_channel_energy = level;
				2'd2: vfb_channel_energy = level << 1;
				default: vfb_channel_energy = level + (level << 1);
			endcase
		end
	endfunction

	function automatic logic [8:0] vfb_soft_cross_energy(
		input logic [8:0] old_energy,
		input logic [8:0] new_energy
	);
		logic [8:0] high_energy;
		logic [8:0] low_energy;
		logic [9:0] sum;
		begin
			high_energy = (old_energy >= new_energy)
				? old_energy : new_energy;
			low_energy = (old_energy >= new_energy)
				? new_energy : old_energy;
			sum = {1'b0, high_energy} + {3'd0, low_energy[8:2]};
			vfb_soft_cross_energy = (sum > VFB_MAX_CHANNEL_ENERGY)
				? VFB_MAX_CHANNEL_ENERGY : sum[8:0];
		end
	endfunction

	function automatic logic [1:0] vfb_quantize_coefficient(
		input logic [8:0] energy,
		input logic [6:0] intensity
	);
		logic [9:0] energy_x2;
		logic [9:0] intensity_x1;
		logic [9:0] intensity_x3;
		logic [9:0] intensity_x5;
		begin
			energy_x2 = {1'b0, energy} << 1;
			intensity_x1 = {3'd0, intensity};
			intensity_x3 = intensity_x1 + (intensity_x1 << 1);
			intensity_x5 = intensity_x1 + (intensity_x1 << 2);

			if ((intensity == 7'd0) || (energy_x2 <= intensity_x1))
				vfb_quantize_coefficient = 2'd0;
			else if (energy_x2 <= intensity_x3)
				vfb_quantize_coefficient = 2'd1;
			else if (energy_x2 <= intensity_x5)
				vfb_quantize_coefficient = 2'd2;
			else
				vfb_quantize_coefficient = 2'd3;
		end
	endfunction

	function automatic logic [8:0] vfb_peak_energy(
		input logic [8:0] red_energy,
		input logic [8:0] green_energy,
		input logic [8:0] blue_energy
	);
		logic [8:0] peak;
		begin
			peak = (red_energy >= green_energy) ? red_energy : green_energy;
			vfb_peak_energy = (blue_energy > peak) ? blue_energy : peak;
		end
	endfunction

	function automatic logic [6:0] vfb_normalize_peak(
		input logic [8:0] peak
	);
		logic [8:0] normalized_intensity;
		logic [9:0] rounded_peak;
		logic [17:0] scaled_peak;
		begin
			rounded_peak = {1'b0, peak} + 10'd2;
			scaled_peak = rounded_peak * 8'd171;

			if (peak == 9'd0)
				normalized_intensity = 9'd0;
			else if (peak <= 9'd127)
				normalized_intensity = peak;
			else if (peak <= 9'd254)
				normalized_intensity = (peak + 9'd1) >> 1;
			else
				// Exact ceil(peak / 3) over the channel-energy range.
				normalized_intensity = {2'd0, scaled_peak[15:9]};

			vfb_normalize_peak = normalized_intensity[6:0];
		end
	endfunction

	function automatic logic [6:0] vfb_normalize_intensity(
		input logic [8:0] red_energy,
		input logic [8:0] green_energy,
		input logic [8:0] blue_energy
	);
		begin
			vfb_normalize_intensity = vfb_normalize_peak(
				vfb_peak_energy(red_energy, green_energy, blue_energy));
		end
	endfunction

	function automatic logic [5:0] vfb_normalize_color(
		input logic [8:0] red_energy,
		input logic [8:0] green_energy,
		input logic [8:0] blue_energy,
		input logic [6:0] intensity
	);
		begin
			vfb_normalize_color = (intensity == 7'd0) ? 6'd0 : {
				vfb_quantize_coefficient(red_energy, intensity),
				vfb_quantize_coefficient(green_energy, intensity),
				vfb_quantize_coefficient(blue_energy, intensity)
			};
		end
	endfunction

	function automatic logic [12:0] vfb_normalize_energies(
		input logic [8:0] red_energy,
		input logic [8:0] green_energy,
		input logic [8:0] blue_energy
	);
		logic [6:0] intensity;
		logic [5:0] color;
		begin
			intensity = vfb_normalize_intensity(
				red_energy, green_energy, blue_energy);
			color = vfb_normalize_color(
				red_energy, green_energy, blue_energy, intensity);
			vfb_normalize_energies = (intensity == 7'd0)
				? 13'd0 : {color, intensity};
		end
	endfunction

endpackage
