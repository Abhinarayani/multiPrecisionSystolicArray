// bitsys_pkg.sv
// Package for BitSys multi-precision systolic array
// Based on: "Bitwise Systolic Array Architecture for Runtime-Reconfigurable
//            Multi-precision Quantized Multiplication on Hardware Accelerators"

package bitsys_pkg;

    // Precision mode encoding (matches paper's 1/2/4/8-bit support)
    // n_channels = 8 >> prec  (channels active per multiplier)
    // bits_per_ch = 1 << prec (bits per operand per channel)
    localparam logic [1:0] PREC_1B = 2'b00; // 8 channels of 1-bit  (BNN / AND)
    localparam logic [1:0] PREC_2B = 2'b01; // 4 channels of 2-bit
    localparam logic [1:0] PREC_4B = 2'b10; // 2 channels of 4-bit
    localparam logic [1:0] PREC_8B = 2'b11; // 1 channel  of 8-bit

    // Systolic array default size
    localparam int SA_SIZE = 4;

endpackage
