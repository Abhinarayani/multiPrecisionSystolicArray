// bitsys_pe_t1.sv
// BitSys Bitwise Processing Element - Type I
//
// Located on the main diagonal of the 8x8 bitwise systolic array (Region I).
// Switches between:
//   xnor_mode=1  : XNOR(in0, in1)  -- BNN ±1 multiplication
//   xnor_mode=0  : AND (in0, in1)  -- standard bit multiplication
//
// Valid signal tracks whether both inputs carry real data.
// When either input is invalid, result_valid=0 prevents wrong accumulation.
//
// Mapped to a single LUT6_2 primitive on Xilinx FPGAs (see paper Fig. 5c).

module bitsys_pe_t1 (
    input  logic in0,          // bit a_i
    input  logic in1,          // bit b_j  (i == j for Type I placement)
    input  logic in0_valid,    // a_i carries real data
    input  logic in1_valid,    // b_j carries real data
    input  logic xnor_mode,   // 1 = XNOR (BNN), 0 = AND (normal)
    output logic result,
    output logic result_valid
);
    assign result       = xnor_mode ? ~(in0 ^ in1) : (in0 & in1);
    assign result_valid = in0_valid & in1_valid;

endmodule
