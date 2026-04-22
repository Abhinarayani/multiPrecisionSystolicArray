// bitsys_mul.sv
// BitSys Multi-Precision Multiplier (combinational, base version)
//
// Implements the BitSys architecture from the paper:
//   A×B = Σ_{i,j} ± a_i · b_j · 2^(i+j)
//
// The 8×8 array of 1-bit PEs computes sub-partial products a_i·b_j.
// A precision-dependent mask selects active PE outputs.
// Sign correction handles 2's-complement signed multiplication per channel.
//
// KEY DESIGN NOTE – per-channel accumulation:
//   In hardware, carry-cutter modules in the output generator pipeline (Fig. 7)
//   prevent signed carry from bleeding between channels.  In this RTL model we
//   mimic carry-cutters by accumulating each channel independently with
//   channel-relative shifts, then packing the channel results into 'product'.
//
// --- Precision Encoding ---
//   prec=2'b11 (PREC_8B): 1  channel  of  8-bit → product[15:0]
//   prec=2'b10 (PREC_4B): 2  channels of  4-bit → product[7:0]/[15:8]
//   prec=2'b01 (PREC_2B): 4  channels of  2-bit → product[3:0]…[15:12]
//   prec=2'b00 (PREC_1B): 8  channels of  1-bit → product[1:0]…[15:14]
//
// --- Sub-Partial Product Mask ---
//   PE(i,j) active iff i and j belong to the same channel:
//     8-bit: always
//     4-bit: (i>>2)==(j>>2)  — two 4×4 diagonal blocks
//     2-bit: (i>>1)==(j>>1)  — four 2×2 diagonal blocks
//     1-bit: i==j            — diagonal only (Type I PEs)
//
// --- Sign Correction ---
//   Subtract PE(i,j) iff exactly one of {i mod N_c, j mod N_c} == N_c−1.
//   For 1-bit (N_c=1): both are sign bits → XOR=0 → no subtract.

`include "bitsys_pkg.sv"

module bitsys_mul
    import bitsys_pkg::*;
(
    input  logic [7:0]  a,
    input  logic [7:0]  b,
    input  logic [1:0]  prec,
    input  logic        is_signed,
    input  logic        bnn_mode,    // XNOR for 1-bit BNN (prec==PREC_1B)
    output logic [15:0] product
);

    // -----------------------------------------------------------------------
    // 8×8 sub-partial product array
    // -----------------------------------------------------------------------
    logic pp_raw    [0:7][0:7];   // a[i] AND b[j]  (or XNOR on diagonal in BNN mode)
    logic pp_masked [0:7][0:7];   // after precision mask
    logic pp_sign   [0:7][0:7];   // 1 = subtract this PE's contribution

    // --- Raw AND / XNOR ---
    always_comb begin
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                if ((prec == PREC_1B) && bnn_mode && (i == j))
                    pp_raw[i][j] = ~(a[i] ^ b[j]);
                else
                    pp_raw[i][j] = a[i] & b[j];
    end

    // --- Precision mask ---
    always_comb begin
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++)
                case (prec)
                    PREC_8B: pp_masked[i][j] = pp_raw[i][j];
                    PREC_4B: pp_masked[i][j] = ((i>>2) == (j>>2)) ? pp_raw[i][j] : 1'b0;
                    PREC_2B: pp_masked[i][j] = ((i>>1) == (j>>1)) ? pp_raw[i][j] : 1'b0;
                    PREC_1B: pp_masked[i][j] = (i == j)           ? pp_raw[i][j] : 1'b0;
                    default:  pp_masked[i][j] = pp_raw[i][j];
                endcase
    end

    // --- Sign correction table ---
    always_comb begin
        for (int i = 0; i < 8; i++)
            for (int j = 0; j < 8; j++) begin
                if (!is_signed || (prec == PREC_1B)) begin
                    pp_sign[i][j] = 1'b0;
                end else begin
                    logic i_sign, j_sign;
                    case (prec)
                        PREC_8B: i_sign = (i == 7);
                        PREC_4B: i_sign = ((i & 3) == 3);
                        PREC_2B: i_sign = ((i & 1) == 1);
                        default:  i_sign = 1'b0;
                    endcase
                    case (prec)
                        PREC_8B: j_sign = (j == 7);
                        PREC_4B: j_sign = ((j & 3) == 3);
                        PREC_2B: j_sign = ((j & 1) == 1);
                        default:  j_sign = 1'b0;
                    endcase
                    pp_sign[i][j] = i_sign ^ j_sign;
                end
            end
    end

    // -----------------------------------------------------------------------
    // Output generation – per-channel accumulation with channel-relative shifts
    // Mimics hardware carry-cutters that prevent signed overflow from one
    // channel spilling into the next channel's bit range.
    // -----------------------------------------------------------------------

    // Intermediate accumulators (declared as module-level for always_comb)
    logic signed [17:0] acc8;           // PREC_8B:  one 18-bit accumulator
    logic signed [11:0] acc4 [0:1];     // PREC_4B:  two 12-bit channel accumulators
    logic signed [ 7:0] acc2 [0:3];     // PREC_2B:  four 8-bit channel accumulators
    logic        [ 1:0] acc1 [0:7];     // PREC_1B:  eight 2-bit results

    always_comb begin
        // Defaults
        acc8 = '0;
        for (int c = 0; c < 2; c++) acc4[c] = '0;
        for (int c = 0; c < 4; c++) acc2[c] = '0;
        for (int c = 0; c < 8; c++) acc1[c] = '0;

        case (prec)

            // ----------------------------------------------------------------
            PREC_8B: begin
                for (int i = 0; i < 8; i++)
                    for (int j = 0; j < 8; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc8 = acc8 - 18'(1 << (i+j));
                            else               acc8 = acc8 + 18'(1 << (i+j));
                product = acc8[15:0];
            end

            // ----------------------------------------------------------------
            PREC_4B: begin
                // Channel 0: i,j ∈ [0,3], shift = i+j  (no offset needed, starts at bit 0)
                for (int i = 0; i < 4; i++)
                    for (int j = 0; j < 4; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc4[0] = acc4[0] - 12'(1 << (i+j));
                            else               acc4[0] = acc4[0] + 12'(1 << (i+j));
                // Channel 1: i,j ∈ [4,7], channel-relative shift = i+j−8
                for (int i = 4; i < 8; i++)
                    for (int j = 4; j < 8; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc4[1] = acc4[1] - 12'(1 << (i+j-8));
                            else               acc4[1] = acc4[1] + 12'(1 << (i+j-8));
                product = {acc4[1][7:0], acc4[0][7:0]};
            end

            // ----------------------------------------------------------------
            PREC_2B: begin
                // Channel c: i,j ∈ [2c, 2c+1], channel-relative shift = i+j − 4c
                for (int i = 0; i < 2; i++)
                    for (int j = 0; j < 2; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc2[0] = acc2[0] - 8'(1 << (i+j));
                            else               acc2[0] = acc2[0] + 8'(1 << (i+j));

                for (int i = 2; i < 4; i++)
                    for (int j = 2; j < 4; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc2[1] = acc2[1] - 8'(1 << (i+j-4));
                            else               acc2[1] = acc2[1] + 8'(1 << (i+j-4));

                for (int i = 4; i < 6; i++)
                    for (int j = 4; j < 6; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc2[2] = acc2[2] - 8'(1 << (i+j-8));
                            else               acc2[2] = acc2[2] + 8'(1 << (i+j-8));

                for (int i = 6; i < 8; i++)
                    for (int j = 6; j < 8; j++)
                        if (pp_masked[i][j])
                            if (pp_sign[i][j]) acc2[3] = acc2[3] - 8'(1 << (i+j-12));
                            else               acc2[3] = acc2[3] + 8'(1 << (i+j-12));

                product = {acc2[3][3:0], acc2[2][3:0], acc2[1][3:0], acc2[0][3:0]};
            end

            // ----------------------------------------------------------------
            PREC_1B: begin
                if (bnn_mode) begin
                    // BNN XNOR: each channel is a single ±1 value
                    for (int k = 0; k < 8; k++)
                        acc1[k] = pp_masked[k][k] ? 2'b01 : 2'b11;
                end else begin
                    // 1-bit AND: each channel is 0 or 1 (both operand bits are "sign"
                    // bits in 2's complement 1-bit, so no subtraction needed)
                    for (int k = 0; k < 8; k++)
                        acc1[k] = {1'b0, pp_masked[k][k]};
                end
                product = {acc1[7], acc1[6], acc1[5], acc1[4],
                           acc1[3], acc1[2], acc1[1], acc1[0]};
            end

            default: product = acc8[15:0];

        endcase
    end

endmodule
