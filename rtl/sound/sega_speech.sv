//============================================================================
//  Sega speech board (drawing 800-0294)
//
//  Used by Space Fury, Zektor and Star Trek. An 8035 at 3.12 MHz reads LPC
//  frames out of the speech data ROM and feeds them to an SP0250.
//
//  Interface behavior follows MAME segaspeech.cpp:
//
//    P1 in       latch & 0x7F
//    P1 out      bit 7 low clears T0
//    P2 out      speech data ROM bank; [5:0] selects a 256-byte page
//    I/O read    speech_data[0x100 * (P2 & 0x3F) + addr]
//    I/O write   SP0250 frame byte
//    T0          set when the latch's bit 7 goes 0 -> 1
//    T1          SP0250 DRQ
//    INT         latch bit 7 inverted (asserted while bit 7 is low)
//
//  The main CPU writes the latch at $38 and the control register at $3B.
//  Control bit 3 gates the speech output; bit 5 gates a third CD4053 channel
//  fed from off-board, which on Star Trek is the Universal Sound Board.
//
//  The 8035's program ROM is 2K mirrored at $0800, which the address mask
//  below reproduces.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_speech #(
	parameter int CLK_HZ  = 15_468_480,   // machine master domain
	parameter int CPU_HZ  =  3_120_000,   // speech board master clock
	// FILTER=0 bypasses the board output filter.
	parameter bit FILTER    = 1'b1,
	parameter bit C10_TENTH = 1'b0
) (
	input  wire        clk,
	input  wire        reset,

	// from the main CPU
	input  wire        data_wr,      // $38, one cycle
	input  wire        ctrl_wr,      // $3B, one cycle
	input  wire  [7:0] din,

	// ROM load
	input  wire        rom_wr,
	input  wire [14:0] rom_addr,     // 0x0000-0x07FF cpu, 0x0800-0x47FF data
	input  wire  [7:0] rom_data,

	// off-board audio input, gated by control bit 5
	input  wire signed [15:0] aux_audio,

	output wire signed [15:0] audio,

	// simulation taps; unused on hardware and pruned by synthesis
	output wire [10:0] dbg_prog_addr,
	output wire        dbg_sp_wr,
	output wire  [7:0] dbg_sp_data,
	output wire        dbg_drq,
	output wire        dbg_t0,
	output wire  [7:0] dbg_p1,
	output wire        dbg_rd_n,
	output wire [13:0] dbg_data_addr,
	output wire        dbg_int_n,
	output wire signed [7:0] dbg_dac
);

	// ------------------------------------------------------------------
	// 3.12 MHz clock enable
	// ------------------------------------------------------------------
	localparam logic [24:0] MASTER_HZ = 25'(CLK_HZ);
	localparam logic [24:0] SPEECH_HZ = 25'(CPU_HZ);

	logic [24:0] acc;
	logic        ce;
	wire [24:0]  acc_next = acc + SPEECH_HZ;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc <= '0;
			ce  <= 1'b0;
		end else if (acc_next >= MASTER_HZ) begin
			acc <= acc_next - MASTER_HZ;
			ce  <= 1'b1;
		end else begin
			acc <= acc_next;
			ce  <= 1'b0;
		end
	end

	// ------------------------------------------------------------------
	// Host-facing latch and control register
	// ------------------------------------------------------------------
	logic [7:0] latch;
	logic [7:0] control;
	logic       t0;
	logic       p1_7_d;

	// Clear T0 when a P1 write drives bit 7 from high to low.
	wire p1_7_fall = ce && !p1_out[7] && p1_7_d;

	always_ff @(posedge clk) begin
		if (reset) begin
			// Reset high so /INT starts deasserted.
			latch   <= 8'h80;
			control <= 8'h00;
			t0      <= 1'b0;
			p1_7_d  <= 1'b1;
		end else begin
			if (ce) p1_7_d <= p1_out[7];
			if (ctrl_wr) control <= din;
			if (data_wr) begin
				// A rising host-latch bit 7 sets T0.
				if (!latch[7] && din[7]) t0 <= 1'b1;
				latch <= din;
			end
			if (p1_7_fall) t0 <= 1'b0;
		end
	end

	// ------------------------------------------------------------------
	// Program ROM: 2K, mirrored at $0800
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] cpu_rom [0:2047];
	logic [7:0] cpu_rom_q;

	wire rom_wr_cpu  = rom_wr && (rom_addr < 15'h0800);
	wire rom_wr_data = rom_wr && (rom_addr >= 15'h0800) && (rom_addr < 15'h4800);

	// ------------------------------------------------------------------
	// Speech data ROM: 16K, paged 256 bytes at a time by P2[5:0]
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] data_rom [0:16383];
	logic [7:0] data_rom_q;

	// ------------------------------------------------------------------
	// 8035
	// ------------------------------------------------------------------
	wire        psen_n, rd_n, wr_n, ale, prog_n;
	wire  [7:0] cpu_do, p1_out, p2_out;
	wire        cpu_t0_out;
	logic [7:0] cpu_di;
	logic [7:0] addr_lo;      // latched from the multiplexed bus by ALE
	logic [7:0] p2_lat;       // P2 sampled at the same ALE edge

	// Capture the multiplexed low byte and P2 together on ALE's falling edge.
	logic ale_d;
	always_ff @(posedge clk) begin
		if (reset) begin
			addr_lo <= 8'd0;
			p2_lat  <= 8'd0;
			ale_d   <= 1'b0;
		end else if (ce) begin
			ale_d <= ale;
			if (!ale && ale_d) begin
				addr_lo <= cpu_do;
				p2_lat  <= p2_out;
			end
		end
	end

	// Program and MOVX addresses use P2 captured with the low address byte.
	// Program ROM is 2K mirrored at $0800, so only 11 bits matter.
	wire [10:0] prog_addr = {p2_lat[2:0], addr_lo};
	wire [13:0] data_addr = {p2_lat[5:0], addr_lo};

	// Registered on clk, not ce. Consecutive CPU enables are at least four
	// master clocks apart, so the data is ready within the 8035 cycle.
	always_ff @(posedge clk) begin
		cpu_rom_q  <= cpu_rom[prog_addr];
		data_rom_q <= data_rom[data_addr];
	end

	always_comb begin
		cpu_di = 8'hFF;
		if (!psen_n)     cpu_di = cpu_rom_q;    // program fetch
		else if (!rd_n)  cpu_di = data_rom_q;   // MOVX read: speech data
	end

	i8035 cpu (
		.clk     (clk),
		.ce      (ce),
		.I_RSTn  (~reset),
		.I_INTn  (latch[7]),        // INT asserted while bit 7 is low
		.I_EA    (1'b1),            // 8035 has no internal ROM
		.O_PSENn (psen_n),
		.O_RDn   (rd_n),
		.O_WRn   (wr_n),
		.O_ALE   (ale),
		.O_PROGn (prog_n),
		.I_T0    (t0),
		.O_T0    (cpu_t0_out),
		.I_T1    (sp_drq),
		.I_DB    (cpu_di),
		.O_DB    (cpu_do),
		.I_P1    ({1'b0, latch[6:0]}),   // P1 input is latch & 0x7F
		.O_P1    (p1_out),
		.I_P2    (8'hFF),
		.O_P2    (p2_out)
	);

	// ------------------------------------------------------------------
	// SP0250
	// ------------------------------------------------------------------
	// Capture MOVX data while /WR is low and strobe the SP0250 on release.
	logic wr_n_d;
	logic [7:0] wr_data;
	always_ff @(posedge clk) begin
		if (reset) begin
			wr_n_d  <= 1'b1;
			wr_data <= 8'd0;
		end else if (ce) begin
			wr_n_d <= wr_n;
			if (!wr_n) wr_data <= cpu_do;
		end
	end
	wire sp_wr = ce && wr_n && !wr_n_d;

	wire       sp_drq;
	wire signed [7:0] sp_dac;
	wire       sp_stb;

	sp0250 synth (
		.clk          (clk),
		.ce           (ce),
		.reset        (reset),
		.wr           (sp_wr),
		.din          (wr_data),
		.drq          (sp_drq),
		.dac          (sp_dac),
		.sample_stb   (sp_stb),
		.sample_start (),
		.dbg_fifo_pos (),
		.dbg_repeat   (),
		.dbg_rcount   (),
		.dbg_pcount   (),
		.dbg_amp      ()
	);

	assign dbg_prog_addr = prog_addr;
	assign dbg_sp_wr     = sp_wr;
	assign dbg_sp_data   = wr_data;
	assign dbg_drq       = sp_drq;
	assign dbg_t0        = t0;
	assign dbg_p1        = p1_out;
	assign dbg_rd_n      = rd_n;
	assign dbg_data_addr = data_addr;
	assign dbg_int_n     = latch[7];
	assign dbg_dac       = sp_dac;

	// ------------------------------------------------------------------
	// ROM load
	// ------------------------------------------------------------------
	always_ff @(posedge clk) begin
		if (rom_wr_cpu)  cpu_rom[rom_addr[10:0]] <= rom_data;
		if (rom_wr_data) data_rom[rom_addr[13:0] - 14'h0800] <= rom_data;
	end

	// ------------------------------------------------------------------
	// Output mix. Control bit 3 gates speech and bit 5 gates the off-board
	// sound board, both through a CD4053.
	// ------------------------------------------------------------------
	// Filter the SP0250 before the CD4053 output gate.
	wire signed [15:0] sp_filtered;

	speech_filter #(.C10_TENTH(C10_TENTH)) filt (
		.clk   (clk),
		.reset (reset),
		.ce    (ce),
		.dac   (sp_dac),
		.audio (sp_filtered)
	);

	wire signed [15:0] speech_out = control[3]
	                              ? (FILTER ? sp_filtered : {sp_dac, 8'd0})
	                              : 16'sd0;
	wire signed [15:0] aux_out = control[5] ? aux_audio : 16'sd0;

	sega_audio_sat_add output_mix (
		.a (speech_out),
		.b (aux_out),
		.y (audio)
	);

endmodule

`default_nettype wire
