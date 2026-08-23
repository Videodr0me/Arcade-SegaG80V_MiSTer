//============================================================================
//  Sega G-80 X-Y machine clock
//
//  The G-80 X-Y boards run from a 15.46848 MHz crystal. Integer enables in
//  sega_machine_timing preserve the original CPU and vector-clock phases.
//============================================================================

module sega_clocks
(
	input  logic refclk,
	input  logic reset,
	output logic clk_master,
	output logic locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("15.468480 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) vec_pll (
		.refclk(refclk),
		.rst(reset),
		.outclk(clk_master),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0)
	);

endmodule
