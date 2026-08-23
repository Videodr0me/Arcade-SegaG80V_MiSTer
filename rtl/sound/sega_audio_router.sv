//============================================================================
//  Sega G-80 X-Y cabinet audio routing
//============================================================================

`default_nettype none

module sega_audio_sat_add (
	input  wire signed [15:0] a,
	input  wire signed [15:0] b,
	output wire signed [15:0] y
);
	wire signed [16:0] sum = {a[15], a} + {b[15], b};

	assign y = (sum >  17'sd32767) ?  16'sh7FFF :
	           (sum < -17'sd32768) ? -16'sh8000 : sum[15:0];
endmodule

module sega_audio_router (
	input  wire        [2:0] game,
	input  wire              pause,
	input  wire signed [15:0] speech_audio,
	input  wire signed [15:0] usb_audio,
	input  wire signed [15:0] discrete_audio,
	output logic signed [15:0] speech_aux,
	output wire signed [15:0] audio
);
	import sega_game_pkg::*;

	// The Zektor board already contains the AY channels. Its speech-board
	// external-input trim is 179/256, approximately 0.7.
	wire signed [24:0] zektor_product = discrete_audio * 9'sd179;
	wire signed [16:0] zektor_scaled = zektor_product[24:8];
	wire signed [15:0] zektor_aux =
		(zektor_scaled >  17'sd32767) ?  16'sh7FFF :
		(zektor_scaled < -17'sd32768) ? -16'sh8000 : zektor_scaled[15:0];

	always_comb begin
		speech_aux = 16'sd0;
		case (game)
			GAME_SPACFURY: speech_aux = discrete_audio;
			GAME_ZEKTOR:   speech_aux = zektor_aux;
			GAME_STARTREK: speech_aux = usb_audio;
			default:;
		endcase
	end

	logic signed [15:0] routed_audio;
	always_comb begin
		routed_audio = 16'sd0;
		case (game)
			GAME_ELIM2,
			GAME_ELIM2C,
			GAME_ELIM4:    routed_audio = discrete_audio;
			GAME_SPACFURY,
			GAME_ZEKTOR,
			GAME_STARTREK: routed_audio = speech_audio;
			GAME_TACSCAN:  routed_audio = usb_audio;
			default:;
		endcase
	end

	// Apply game-specific output gain, then saturate.
	wire signed [18:0] routed_ext = {{3{routed_audio[15]}}, routed_audio};
	logic signed [18:0] gained_audio;

	always_comb begin
		case (game)
			GAME_TACSCAN:  gained_audio = routed_ext <<< 1;  // +6.02 dB
			GAME_STARTREK: gained_audio = routed_ext + (routed_ext >>> 2)
			                              + (routed_ext >>> 3)
			                              + (routed_ext >>> 5); // +2.96 dB
			default:       gained_audio = routed_ext;
		endcase
	end

	wire signed [15:0] levelled_audio =
		(gained_audio >  19'sd32767) ?  16'sh7FFF :
		(gained_audio < -19'sd32768) ? -16'sh8000 : gained_audio[15:0];

	assign audio = pause ? 16'sd0 : levelled_audio;
endmodule

`default_nettype wire
