//============================================================================
//  Sega G-80 X-Y machine timing
//
//  The CPU, vector, interrupt, and Zektor AY clocks are divided from the
//  15.46848 MHz X-Y master. One shared phase counter keeps their relationship
//  deterministic.
//============================================================================

`default_nettype none

module sega_machine_timing
(
	input  wire clk,
	input  wire reset,
	input  wire pause,

	output wire ce_cpu,
	output wire ce_vcl,
	output wire ce_vcl_2x,
	output wire ce_ay,
	output wire edgint
);
	localparam logic [16:0] EDGINT_DIV = 17'h1F788;

	logic [4:0] phase;
	logic [16:0] edgint_count;

	wire ce_u34 = (phase == 5'd2)  || (phase == 5'd5)  ||
	              (phase == 5'd8)  || (phase == 5'd11) ||
	              (phase == 5'd14) || (phase == 5'd17) ||
	              (phase == 5'd20) || (phase == 5'd23);

	assign ce_cpu = !pause && (phase[1:0] == 2'd3);       // master / 4
	assign ce_vcl = (phase == 5'd5)  || (phase == 5'd11) ||
	                (phase == 5'd17) || (phase == 5'd23); // master / 6
	assign ce_vcl_2x = ce_u34;                            // master / 3
	assign ce_ay  = (phase[2:0] == 3'd7);                 // master / 8
	assign edgint = ce_u34 && (edgint_count == EDGINT_DIV - 1'd1);

	always_ff @(posedge clk) begin
		if (reset) begin
			phase <= 5'd0;
			edgint_count <= 17'd0;
		end else begin
			phase <= (phase == 5'd23) ? 5'd0 : phase + 1'd1;
			if (ce_u34)
				edgint_count <= edgint ? 17'd0 : edgint_count + 1'd1;
		end
	end

endmodule

`default_nettype wire
