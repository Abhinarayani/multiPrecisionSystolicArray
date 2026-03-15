// bitsys_mac.sv
// BitSys Multiply-Accumulate (MAC) Unit
//
// One instance per Processing Element of the outer systolic array.
// Contains: BitSys multiplier + accu input converter + 32-bit accumulator.
//
// --- Clear semantics ---
// When clear=1, the accumulator LOADS the current product (not zeros).
// This matches the hardware where clear and the first valid data arrive
// simultaneously (clear_sr[i+j] fires at posedge i+j; first product also
// arrives at posedge i+j+1 when clear is visible as FF output).
// Subsequent cycles accumulate normally via en.

`include "bitsys_pkg.sv"

module bitsys_mac
    import bitsys_pkg::*;
(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clear,      // load first product (start new dot-product)
    input  logic               en,         // data valid - accumulate
    input  logic [7:0]         a_in,
    input  logic [7:0]         b_in,
    input  logic [1:0]         prec,
    input  logic               is_signed,
    input  logic               bnn_mode,
    output logic [7:0]         a_out,      // registered pass-through (systolic)
    output logic [7:0]         b_out,
    output logic signed [31:0] result
);

    logic [15:0]         mul_product;
    logic signed [19:0]  accu_in;

    bitsys_mul u_mul (
        .a        (a_in),
        .b        (b_in),
        .prec     (prec),
        .is_signed(is_signed),
        .bnn_mode (bnn_mode),
        .product  (mul_product)
    );

    bitsys_accu_conv u_conv (
        .mul_out  (mul_product),
        .prec     (prec),
        .is_signed(is_signed),
        .accu_in  (accu_in)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 32'sd0;
            a_out  <= 8'b0;
            b_out  <= 8'b0;
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            if (clear)
                // Load first product (clear_sr fires same cycle as first data)
                result <= 32'(signed'(accu_in));
            else if (en)
                result <= result + 32'(signed'(accu_in));
        end
    end

endmodule
