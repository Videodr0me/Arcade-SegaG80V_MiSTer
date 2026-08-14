//============================================================================
//  Zektor AY-3-8912
//
//  Clocked at 15.46848 MHz / 8. Port $3C selects a register and $3D writes it.
//  Equal 10K channel loads are modeled by summing JT49's channel outputs.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_ay (
	input  wire        clk,
	input  wire        ce,         // 15.46848 MHz / 8 = 1.93356 MHz
	input  wire        reset,

	input  wire        wr,        // one cycle, from the $3C/$3D I/O strobe
	input  wire        addr_sel,  // 0 = $3C (address latch), 1 = $3D (data)
	input  wire  [7:0] din,

	output wire signed [15:0] audio   // DC-blocked, signed
);

	// Hold each data write until JT49's next clock enable.
	logic [3:0] reg_addr;
	logic       pending;
	logic [7:0] pending_data;

	always_ff @(posedge clk) begin
		if (reset) begin
			reg_addr     <= 4'd0;
			pending      <= 1'b0;
			pending_data <= 8'd0;
		end else begin
			if (wr) begin
				if (!addr_sel) reg_addr <= din[3:0];
				else begin
					pending      <= 1'b1;
					pending_data <= din;
				end
			end
			if (pending && ce) pending <= 1'b0;
		end
	end

	wire [7:0] ch_a, ch_b, ch_c;

	jt49 psg (
		.rst_n   (~reset),
		.clk     (clk),
		.clk_en  (ce),
		.addr    (reg_addr),
		.cs_n    (1'b0),
		.wr_n    (~pending),
		.din     (pending_data),
		.sel     (1'b1),          // no extra divide; ce is already the AY rate
		.dout    (),
		.sound   (),
		.A       (ch_a),
		.B       (ch_b),
		.C       (ch_c),
		.sample  (),
		.IOA_in  (8'hFF), .IOA_out(), .IOA_oe(),
		.IOB_in  (8'hFF), .IOB_out(), .IOB_oe()
	);

	// Sum the unsigned channels and remove their volume-dependent DC.
	wire [10:0] raw = {3'd0, ch_a} + {3'd0, ch_b} + {3'd0, ch_c};
	wire signed [20:0] x = $signed({5'd0, raw, 5'd0});     // 0..24480

	logic signed [20:0] dc;
	always_ff @(posedge clk) begin
		if (reset)       dc <= '0;
		else if (ce)     dc <= dc + ((x - dc) >>> 15);      // ~10 Hz
	end

	wire signed [20:0] ac = x - dc;
	assign audio = (ac >  21'sd32767) ?  16'sh7FFF :
	               (ac < -21'sd32768) ? -16'sh8000 : ac[15:0];

endmodule

`default_nettype wire
