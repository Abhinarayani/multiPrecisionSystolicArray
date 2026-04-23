// bitsys_accu_conv.sv
// Multi-Precision Accumulator Input Converter  (Fig. 8 in paper)
//
// Converts the 16-bit packed multi-channel multiplier output into a single
// signed 20-bit value suitable for accumulation.
//
// The tree structure (Fig. 8) applies the per-channel bit-weight (2^i) and
// sign-bit negation, then sums all channels.  This allows one accumulator +
// one activation module per multiplier regardless of precision mode.
//
// Conversion per mode:
//   PREC_8B (1 ch ×16b) : sign-extend product[15:0] to 20 bits
//   PREC_4B (2 ch ×8b)  : sign-extend ch0[7:0] + sign-extend ch1[7:0]
//   PREC_2B (4 ch ×4b)  : sum of four sign-extended 4-bit channels
//   PREC_1B (8 ch ×2b)  : sum of eight sign-extended 2-bit channels
//                          (±1 in XNOR BNN mode → popcount−N equivalent)

module bitsys_accu_conv
    import bitsys_pkg::*;
(
    input  logic [15:0]       mul_out,
    input  logic [1:0]        prec,
    input  logic              is_signed,
    output logic signed [19:0] accu_in   // summed channel value for accumulation
);

    always_comb begin
        case (prec)

            PREC_8B: begin
                // One 16-bit channel
                if (is_signed)
                    accu_in = 20'(signed'(mul_out));
                else
                    accu_in = 20'({1'b0, mul_out});
            end

            PREC_4B: begin
                // Two 8-bit channels packed as [15:8]=ch1, [7:0]=ch0
                logic signed [19:0] ch0, ch1;
                if (is_signed) begin
                    ch0 = 20'(signed'(mul_out[7:0]));
                    ch1 = 20'(signed'(mul_out[15:8]));
                end else begin
                    ch0 = 20'({1'b0, mul_out[7:0]});
                    ch1 = 20'({1'b0, mul_out[15:8]});
                end
                accu_in = ch0 + ch1;
            end

            PREC_2B: begin
                // Four 4-bit channels: [3:0], [7:4], [11:8], [15:12]
                logic signed [19:0] ch [0:3];
                for (int k = 0; k < 4; k++) begin
                    logic [3:0] raw;
                    raw = mul_out[4*k +: 4];
                    ch[k] = is_signed ? 20'(signed'(raw)) : 20'({1'b0, raw});
                end
                accu_in = ch[0] + ch[1] + ch[2] + ch[3];
            end

            PREC_1B: begin
                // Eight 2-bit channels: product[2k+1:2k]
                // In XNOR BNN mode each channel is 2'b01(+1) or 2'b11(−1)
                logic signed [19:0] ch [0:7];
                for (int k = 0; k < 8; k++) begin
                    logic [1:0] raw;
                    raw = mul_out[2*k +: 2];
                    ch[k] = is_signed ? 20'(signed'(raw)) : 20'({1'b0, raw});
                end
                accu_in = ch[0] + ch[1] + ch[2] + ch[3] +
                          ch[4] + ch[5] + ch[6] + ch[7];
            end

            default: accu_in = 20'(signed'(mul_out));

        endcase
    end

endmodule
