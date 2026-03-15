// bitsys_pe_t2.sv
// BitSys Bitwise Processing Element - Type II
//
// Located in off-diagonal regions (Region II / III / IV) of the 8x8 array.
// The sub-partial product mask enables or zeros this PE based on precision:
//   mask_en=1 : compute AND(in0, in1)   -- PE active for current precision
//   mask_en=0 : output 0                -- PE masked out (filtered)
//
// mask_en is derived externally from the precision mode (prec[1:0]) and
// the PE's (row, col) position relative to channel boundaries.

module bitsys_pe_t2 (
    input  logic in0,
    input  logic in1,
    input  logic in0_valid,
    input  logic in1_valid,
    input  logic mask_en,     // precision-based sub-partial-product mask
    output logic result,
    output logic result_valid
);
    assign result       = mask_en & in0 & in1;
    assign result_valid = mask_en & in0_valid & in1_valid;

endmodule
