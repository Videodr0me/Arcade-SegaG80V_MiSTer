//============================================================================
//  Asynchronous-assert, synchronous-release reset
//============================================================================

module sega_reset_sync (
	input  logic clk,
	input  logic reset_async,
	output logic reset
);

	logic [1:0] reset_pipe = 2'b11;

	always_ff @(posedge clk or posedge reset_async) begin
		if (reset_async)
			reset_pipe <= 2'b11;
		else
			reset_pipe <= {reset_pipe[0], 1'b0};
	end

	assign reset = reset_pipe[1];

endmodule
