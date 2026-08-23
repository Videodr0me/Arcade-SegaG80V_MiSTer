//============================================================================
//  Sega G-80 X-Y (vector) arcade hardware for MiSTer FPGA
//
//  Eliminator, Space Fury, Zektor, Tac/Scan, Star Trek.
//  Original hardware by Sega/Gremlin, 1981-1982.
//
//  Vector renderer and CRT pipeline by Videodr0me
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	`include "build_id.v"

	logic [127:0] status;
	logic  [31:0] joystick_0;
	logic  [31:0] joystick_1;
	logic  [31:0] joystick_2;
	logic  [31:0] joystick_3;
	logic  [15:0] analog_0;
	logic  [15:0] analog_1;
	logic   [8:0] spinner_0;
	logic   [8:0] spinner_1;
	logic  [24:0] ps2_mouse;
	logic   [1:0] buttons;
	logic         direct_video;
	wire   [21:0] gamma_bus;

	logic         ioctl_download;
	logic         ioctl_wr;
	logic  [26:0] ioctl_addr;
	logic   [7:0] ioctl_dout;
	logic  [15:0] ioctl_index;

	logic clk_master;   // 15.46848 MHz Sega machine master
	logic clk_125;
	logic pll_locked;
	logic master_pll_locked;

	logic         video_supports_120hz;
	logic         video_mode_toggle;
	logic         video_freeze;
	logic         video_field;
	logic         video_is_15khz;
	logic   [7:0] game_id = 8'd0;
	wire    [2:0] game = game_id[2:0];
	wire    [2:0] cfg_chip;
	wire          cfg_usb;
	wire          cfg_speech;
	wire    [1:0] cfg_fc;
	wire    [2:0] cfg_orient;
	wire          cfg_open_matte;
	wire    [1:0] cfg_matte_axes;
	wire          spinner_game = (cfg_fc == 2'd1);
	wire    [1:0] open_matte = !status[125] ? cfg_matte_axes : 2'b00;

	wire [2:0] profile = status[68:66] + 3'd2;
	wire profile_off        = (profile == 3'd0);
	wire profile_touch      = (profile == 3'd1);
	wire profile_typical    = (profile == 3'd2);
	wire profile_overdriven = (profile == 3'd3);
	wire profile_neon       = (profile == 3'd4);
	wire profile_stranger   = (profile == 3'd5);
	wire profile_custom_1   = (profile == 3'd6);
	wire profile_custom_2   = (profile == 3'd7);

	wire [2:0] custom_bloom_width =
		profile_custom_2 ? status[99:97] : status[76:74];
	wire [2:0] custom_halo =
		profile_custom_2 ? status[105:103] : status[82:80];
	wire custom_bloom_off =
		(profile_custom_1 || profile_custom_2) &&
		(custom_bloom_width == 3'd0);
	wire custom_halo_off =
		(profile_custom_1 || profile_custom_2) &&
		(custom_halo == 3'd0);

	// Menu order starts with Off; the internal tone-map code for Off is 3.
	wire [1:0] custom_1_tone_mapping = status[73:72] + 2'd3;
	wire [1:0] custom_2_tone_mapping = status[96:95] + 2'd3;
	wire [29:0] custom_1_settings = {
		status[42:41], status[59:57], status[71:69],
		custom_1_tone_mapping, status[76:74], status[79:77],
		status[82:80], status[84:83], status[86:85], status[88:87],
		status[121], status[91:89], status[122]
	};
	wire [29:0] custom_2_settings = {
		status[44:43], status[62:60], status[94:92],
		custom_2_tone_mapping, status[99:97], status[102:100],
		status[105:103], status[107:106], status[109:108], status[111:110],
		status[123], status[114:112], status[124]
	};

	//============================================================
	// OSD
	//============================================================
	localparam CONF_STR = {
		"SegaG80V;;",
		"-;",
		"P1,Video Profiles & Effects;",
		"P1-;",
		"P1O[68:66],Profile,80s Cruise Control,80s Overdrive,Neon Fever Dream,Mutara Nebula,Custom 1,Custom 2,Off,A Touch of CRT;",
		"h5P1-;",
		"h5P1-,CRT effects are bypassed.;",
		"h5P1-;",
		"h5P1-, For advanced settings;",
		"h5P1-, select Custom Profiles 1/2;",
		"h6P1-;",
		"h6P1-,Modern clarity with a touch;",
		"h6P1-,of old. Subtle halo & bloom;",
		"h6P1-,while vectors stay crisp.;",
		"h6P1-;",
		"h6P1-, For advanced settings;",
		"h6P1-, select Custom Profiles 1/2;",
		"h7P1-;",
		"h7P1-,Even richer glow and;",
		"h7P1-,stronger bloom. A restrained;",
		"h7P1-,color vector CRT look.;",
		"h7P1-;",
		"h7P1-, For advanced settings;",
		"h7P1-, select Custom Profiles 1/2;",
		"h8P1-;",
		"h8P1-,The arcade look you remember;",
		"h8P1-,hot vectors and heavy bloom;",
		"h8P1-,phosphor trails linger.;",
		"h8P1-;",
		"h8P1-, For advanced settings;",
		"h8P1-, select Custom Profiles 1/2;",
		"h9P1-;",
		"h9P1-,Midnight arcade. Voltage up.;",
		"h9P1-,Neon color & vector flicker.;",
		"h9P1-,Restless phosphor trails.;",
		"h9P1-;",
		"h9P1-,      Epilepsy warning;",
		"h9P1-,    excessive flashing;",
		"h9P1-,       bright lights;",
		"hAP1-;",
		"hAP1-,Reality leaves the cabinet;",
		"hAP1-,fast sparks and long trails;",
		"hAP1-,cross in the Mutara nebula.;",
		"hAP1-;",
		"hAP1-,      Epilepsy warning;",
		"hAP1-,    excessive flashing;",
		"hAP1-,       bright lights;",
		"hBP1O[71:69],> Dot Scale,2x,2.5x,3x,1x;",
		"hBP1O[73:72],> Tone Mapping,Off,Linear 1,Linear 2,Bright;",
		"hBP1O[76:74],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hBH3P1O[79:77],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hBP1O[82:80],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hBH4P1O[59:57],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hBH4P1O[84:83],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hBH4P1O[42:41],> Halo Compression,16,32,8,24;",
		"hBP1O[86:85],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hBP1O[88:87],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hBP1O[121],> Color Space,Off,G08 -> 709;",
		"hBP1O[91:89],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hBP1O[122],> Slot Mask,Off,On;",
		"hCP1O[94:92],> Dot Scale,2x,2.5x,3x,1x;",
		"hCP1O[96:95],> Tone Mapping,Off,Linear 1,Linear 2,Bright;",
		"hCP1O[99:97],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hCH3P1O[102:100],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCP1O[105:103],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hCH4P1O[62:60],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hCH4P1O[107:106],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hCH4P1O[44:43],> Halo Compression,16,32,8,24;",
		"hCP1O[109:108],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hCP1O[111:110],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hCP1O[123],> Color Space,Off,G08 -> 709;",
		"hCP1O[114:112],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hCP1O[124],> Slot Mask,Off,On;",
		"P2,Video Timing & Geometry;",
		"P2-;",
		"P2O[7:6],Orientation,Normal,Rotate 90 CW,Rotate 180,Rotate 90 CCW;",
		"hEP2O[125],Open Matte,Yes,No;",
		"P2-;",
		"P2O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
		"D0P2O[25],120Hz (720p only),Off,On;",
		"h1P2O[115],Direct Video Scan Rate,15 kHz,31 kHz;",
		"h2P2O[118],15 kHz Format,480i,240p;",
		"P2-;",
		"P2-,Best left at default:;",
		"P2O[15:14],Aspect Ratio,Optimized,Stretched,Pixel Perfect;",
		"-;",
		"P3,Pause Options;",
		"P3-;",
		"P3O[116],Pause when OSD is open,Off,On;",
		"P3O[117],Dim video after 10s,On,Off;",
		"-;",
		"hDP4,Input Controls;",
		"hDP4-;",
		"hDP4O[2],Direction,Normal,Reversed;",
		"hDP4O[10:8],Sensitivity,1.0x,0.75x,0.5x,0.25x,0.125x,1.25x,1.5x,2.0x;",
		"hD-;",
		"P5,Core Info;",
		"P5-;",
		"P5-,Sega G-80 X-Y vector core;",
		"P5-;",
		"P5-,G80V core by alanswx;",
		"P5-,based on Sega hardware docs;",
		"P5-,and Aaron Giles' MAME work.;",
		"P5-;",
		"P5-,HD renderer & CRT pipeline;",
		"P5-,Input control integration;",
		"P5-,Core fixes & refinements;",
		"P5-,by Videodr0me:;",
		"P5-;",
		"P5-,buymeacoffee.com/videodr0me;",
		"-;",
		"DIP;",
		"-;",
		"R[0],Reset;",
		// bits 4..11: fire1..fire4, start1, start2, coin, pause
		"J1,Fire,Fire 2,Fire 3,Fire 4,Start 1,Start 2,Coin,Pause;",
		"jn,A,B,X,Y,Start,Select,R,L;",
		"V,v1.0.", `BUILD_DATE
	};

	hps_io #(.CONF_STR(CONF_STR)) hps_io_inst (
		.clk_sys(clk_master),
		.HPS_BUS(HPS_BUS),
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_2(joystick_2),
		.joystick_3(joystick_3),
		.joystick_l_analog_0(analog_0),
		.joystick_l_analog_1(analog_1),
		.spinner_0(spinner_0),
		.spinner_1(spinner_1),
		.ps2_mouse(ps2_mouse),
		.buttons(buttons),
		.forced_scandoubler(),
		.direct_video(direct_video),
		.new_vmode(video_mode_toggle),
		.gamma_bus(gamma_bus),
		.status(status),
		.status_menumask({
			1'b0, cfg_open_matte, spinner_game,
			profile_custom_2, profile_custom_1, profile_stranger,
			profile_neon, profile_overdriven, profile_typical,
			profile_touch, profile_off,
			custom_halo_off, custom_bloom_off,
			video_is_15khz, direct_video, !video_supports_120hz
		}),
		.ioctl_download(ioctl_download),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_index(ioctl_index)
	);

	pll pll (
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(clk_125),
		.outclk_1(),
		.outclk_2(),
		.locked(pll_locked)
	);

	sega_clocks machine_clocks (
		.refclk(CLK_50M),
		.reset(1'b0),
		.clk_master(clk_master),
		.locked(master_pll_locked)
	);

	//============================================================
	// MRA payload
	//   index 0   : packed game and sound ROM image; layout in segag80v.sv
	//   index 1   : one game-identifier byte
	//   index 254 : DIP switches
	//============================================================
	logic [7:0] dip_switch [0:7];
	logic dip_download_q = 1'b0;
	logic virtual_controls_loaded = 1'b0;
	logic self_test_event = 1'b0;
	logic service_advance_event = 1'b0;
	wire dip_download = ioctl_download && (ioctl_index == 16'd254);

	initial begin
		dip_switch[0] = 8'hFF;   // SW1
		dip_switch[1] = 8'h33;   // SW2: 1 coin / 1 credit
		dip_switch[2] = 8'h00;   // virtual switches
		dip_switch[3] = 8'hFF;
		dip_switch[4] = 8'hFF;
		dip_switch[5] = 8'hFF;
		dip_switch[6] = 8'hFF;
		dip_switch[7] = 8'hFF;
	end

	always @(posedge clk_master) begin
		dip_download_q <= dip_download;
		if (dip_download_q && !dip_download)
			virtual_controls_loaded <= 1'b1;

		if (ioctl_wr && (ioctl_index == 16'd1))
			game_id <= ioctl_dout;
		if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[26:3]) begin
			if ((ioctl_addr[2:0] == 3'd2) && virtual_controls_loaded) begin
				if (ioctl_dout[0] != dip_switch[2][0])
					self_test_event <= ~self_test_event;
				if (ioctl_dout[1] != dip_switch[2][1])
					service_advance_event <= ~service_advance_event;
			end
			dip_switch[ioctl_addr[2:0]] <= ioctl_dout;
		end
	end

	wire rom_download     = ioctl_download && (ioctl_index == 16'd0);
	wire variant_download = ioctl_download && (ioctl_index == 16'd1);
	wire reset_request = RESET || status[0] || buttons[1] ||
	                     rom_download || variant_download ||
	                     !pll_locked || !master_pll_locked;
	wire reset_master;
	wire reset_125;

	sega_reset_sync reset_sync_master (
		.clk(clk_master),
		.reset_async(reset_request),
		.reset(reset_master)
	);

	sega_reset_sync reset_sync_125 (
		.clk(clk_125),
		.reset_async(reset_request),
		.reset(reset_125)
	);

	// Hold the virtual service switch for 300 ms so the game can poll it.
	localparam logic [22:0] SERVICE_ADVANCE_TICKS = 23'd4_640_544;
	logic [22:0] service_advance_count;
	logic service_advance_event_q;
	always_ff @(posedge clk_master) begin
		if (reset_master) begin
			service_advance_event_q <= service_advance_event;
			service_advance_count   <= '0;
		end else begin
			service_advance_event_q <= service_advance_event;
			if (service_advance_event != service_advance_event_q)
				service_advance_count <= SERVICE_ADVANCE_TICKS;
			else if (service_advance_count != 0)
				service_advance_count <= service_advance_count - 1'b1;
		end
	end

	//============================================================
	// Machine
	//============================================================
	sega_game_cfg gamecfg (
		.game(game), .cfg_chip(cfg_chip), .cfg_usb(cfg_usb),
		.cfg_speech(cfg_speech), .cfg_fc(cfg_fc), .cfg_orient(cfg_orient),
		.cfg_open_matte(cfg_open_matte), .cfg_matte_axes(cfg_matte_axes)
	);

	wire [7:0] in_d7d6, in_d5d4, in_d3d2, in_d1d0, in_fc, in_coins;
	wire       coin_a, coin_b;
	wire       service = ~(|service_advance_count);
	sega_inputs inputs (
		.game(game),
		.joy1(joystick_0), .joy2(joystick_1),
		.joy3(joystick_2), .joy4(joystick_3),
		.dsw1(dip_switch[0]), .dsw2(dip_switch[1]),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.coin_a(coin_a), .coin_b(coin_b)
	);

	wire dpad_l = joystick_0[1] | joystick_1[1];
	wire dpad_r = joystick_0[0] | joystick_1[0];
	wire       spin_stb;
	wire [8:0] spin_magnitude;
	wire       spin_direction;

	sega_spinner_input spinner_input (
		.clk(clk_master),
		.reset(reset_master),
		.game(game),
		.move_left(dpad_l),
		.move_right(dpad_r),
		.analog_x_0($signed(analog_0[7:0])),
		.analog_x_1($signed(analog_1[7:0])),
		.spinner_0(spinner_0),
		.spinner_1(spinner_1),
		.mouse(ps2_mouse),
		.reverse(status[2]),
		.sensitivity(status[10:8]),
		.step_valid(spin_stb),
		.step_magnitude(spin_magnitude),
		.step_direction(spin_direction)
	);

	logic pause_cpu;
	logic [23:0] paused_rgb;
	wire  [7:0] raw_video_r, raw_video_g, raw_video_b;

	pause #(8, 8, 8, 12) pause_inst (
		.clk_sys(clk_master),
		.reset(reset_master),
		.user_button(joystick_0[11] | joystick_1[11] |
		             joystick_2[11] | joystick_3[11]),
		.pause_request(1'b0),
		.options({~status[117], status[116]}),
		.OSD_STATUS(OSD_STATUS),
		.r(raw_video_r), .g(raw_video_g), .b(raw_video_b),
		.pause_cpu(pause_cpu),
		.rgb_out(paused_rgb)
	);

	wire signed [15:0] machine_audio;
	wire       vec_tick;
	wire signed [12:0] vec_x, vec_y;
	wire [5:0] vec_colour;
	wire       vec_beam, vec_valid, vec_frame_done, vec_frame_start, drawing;

	segag80v machine (
		.clk_master(clk_master),
		.reset(reset_master),
		.pause(pause_cpu),
		.cfg_chip(cfg_chip), .cfg_usb(cfg_usb), .cfg_speech(cfg_speech),
		.cfg_game(game),
		.cfg_fc(cfg_fc),
		.rom_wr(ioctl_wr && rom_download),
		.rom_addr(ioctl_addr[16:0]),
		.rom_data(ioctl_dout),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.spin_magnitude(spin_magnitude),
		.spin_direction(spin_direction), .spin_stb(spin_stb),
		.coin_a(coin_a), .coin_b(coin_b), .service(service),
		.self_test(self_test_event),
		.vec_x(vec_x), .vec_y(vec_y), .vec_colour(vec_colour),
		.vec_beam(vec_beam), .vec_valid(vec_valid),
		.drawing(drawing), .frame_done(vec_frame_done),
		.frame_start(vec_frame_start), .vec_tick(vec_tick),
		.snd_wr(), .snd_sel(), .ay_wr(), .ay_port(),
		.speech_data_wr(), .speech_ctrl_wr(), .usb_data_wr(), .snd_data(),
		.audio_ay(), .audio_speech(), .audio_usb(), .audio_discrete(),
		.audio_mix(machine_audio),
		.dbg_usb_tick(), .dbg_usb_noise(), .dbg_usb_tmr(),
		.dbg_usb_cfg(), .dbg_usb_env(),
		.dbg_sp_prog_addr(), .dbg_sp_wr(), .dbg_sp_data(), .dbg_sp_drq(),
		.dbg_sp_t0(), .dbg_sp_p1(), .dbg_sp_rd_n(), .dbg_sp_data_addr(),
		.dbg_sp_int_n(), .dbg_sp_dac(), .coin_counter(),
		.dbg_irq(), .dbg_coin_ff(), .dbg_int_ack()
	);

	//============================================================
	// Video
	//============================================================
	logic sdram_data_oe;
	logic [15:0] sdram_data_out;
	logic  [1:0] sdram_dqm;
	logic video_hblank, video_vblank;
	logic fifo_full;

	assign SDRAM_CLK  = ~clk_125;
	assign SDRAM_DQ   = sdram_data_oe ? sdram_data_out : 16'hzzzz;
	assign SDRAM_DQML = sdram_dqm[0];
	assign SDRAM_DQMH = sdram_dqm[1];

	sega_video video (
		.clk_master(clk_master),
		.vec_tick(vec_tick),
		.clk_50(CLK_50M),
		.clk_125(clk_125),
		.reset(reset_125),
		.upload_reset(!pll_locked),
		.reset_source(reset_master),
		.direct_video(direct_video),
		.direct_video_31khz(status[115]),
		.crt_15khz_480i(!status[118]),
		.hdmi_height(HDMI_HEIGHT),
		.aspect_ratio(status[15:14]),
		.game_orientation(cfg_orient),
		.screen_rotation(status[7:6]),
		.open_matte(open_matte),

		.vec_x(vec_x), .vec_y(vec_y), .vec_colour(vec_colour),
		.vec_beam(vec_beam), .vec_valid(vec_valid),
		.frame_done(vec_frame_done), .frame_start(vec_frame_start),

		.osd_flash_param(8'd0),
		.osd_120hz(status[25]),
		.osd_buffer_mode(status[40:39]),
		.profile(profile),
		.custom_1_settings(custom_1_settings),
		.custom_2_settings(custom_2_settings),

		.video_arx(VIDEO_ARX), .video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(video_hblank), .vblank(video_vblank),
		.video_r(raw_video_r), .video_g(raw_video_g), .video_b(raw_video_b),
		.hsync(VGA_HS), .vsync(VGA_VS),
		.field(video_field),
		.mode_supports_120hz(video_supports_120hz),
		.mode_is_15khz(video_is_15khz),
		.video_mode_toggle(video_mode_toggle),
		.video_freeze(video_freeze),
		.fifo_full(fifo_full),

		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),

		.sdram_data_in(SDRAM_DQ),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(sdram_dqm),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign CLK_VIDEO = clk_125;
	assign VGA_R = paused_rgb[23:16];
	assign VGA_G = paused_rgb[15:8];
	assign VGA_B = paused_rgb[7:0];
	assign VGA_DE = !(video_hblank || video_vblank);
	assign VGA_F1 = video_field;
	assign VGA_SL = 2'b00;
	assign VGA_SCALER = 1'b0;
	assign VGA_DISABLE = 1'b0;
	assign HDMI_FREEZE = video_freeze;
	assign HDMI_BLACKOUT = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	assign AUDIO_L = machine_audio;
	assign AUDIO_R = machine_audio;
	assign AUDIO_S = 1'b1;
	assign AUDIO_MIX = 2'b00;

	assign LED_USER  = fifo_full || ioctl_download;
	assign LED_DISK  = 2'b00;
	assign LED_POWER = 2'b00;
	assign BUTTONS   = 2'b00;

	assign ADC_BUS = 4'bzzzz;
	assign USER_OUT = 7'h7f;
	assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
	assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;

`ifdef MISTER_FB
	assign FB_EN = 1'b0;
	assign FB_FORMAT = 5'd0;
	assign FB_WIDTH = 12'd0;
	assign FB_HEIGHT = 12'd0;
	assign FB_BASE = 32'd0;
	assign FB_STRIDE = 14'd0;
	assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
	assign FB_PAL_CLK = 1'b0;
	assign FB_PAL_ADDR = 8'd0;
	assign FB_PAL_DOUT = 24'd0;
	assign FB_PAL_WR = 1'b0;
`endif
`endif

`ifdef MISTER_DUAL_SDRAM
	assign SDRAM2_CLK = 1'bz;
	assign SDRAM2_A = 13'hzzz;
	assign SDRAM2_BA = 2'bzz;
	assign SDRAM2_DQ = 16'hzzzz;
	assign {SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 4'hf;
`endif

endmodule
