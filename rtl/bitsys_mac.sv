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
//
// --- Input Sparsity Bypass ---
// Each PE independently detects whether its own a_in operand is all-zero
// using an 8-input OR-reduction.  When a_in == 8'h00 AND bnn_mode == 0,
// three power savings activate simultaneously:
//
//   1. a_gated = 8'h00 → all 64 sub-partial-product AND gates in
//      bitsys_mul output 0 → combinational switching suppressed.
//
//   2. accu_en = clear | (en & ~pe_skip) → clk_accu gated off on en cycles →
//      accumulator FF does not clock when merely accumulating zeros.
//      clear is never masked: it must fire to reset the accumulator to 0
//      at the start of a new operation, even when a_in is all-zero.
//
//   3. data_en = en (NOT masked by pe_skip) — a_out/b_out always shift so
//      that zero propagates right-to-left, letting downstream PEs self-skip.
//
// Deriving pe_skip from a_in (the already-skewed, already-passed-through
// value arriving at this specific PE) means each PE self-qualifies.
// No external pipeline or cross-module signal is required.  The timing is
// automatically correct because a_in already carries the data for this PE
// at this cycle — if it is zero, the contribution is zero regardless of
// what other PEs in the same row are seeing.
//
// When clear fires on a zero-input cycle, the accumulator loads accu_in=0
// (because a_gated=0), initialising it to zero without extra state.
//
// BNN mode (bnn_mode=1) forces pe_skip=0: in XNOR ±1 encoding the bit
// value 0 means −1, not absence of data.  There are no zero activations
// in BNN layers.
//
// --- Clock Gating ---
// Uses integrated clock gating (ICG) cells to reduce dynamic power:
//   - Accumulator gated with enable = clear | (en & ~pe_skip)
//   - Data path  gated with enable = en  (pe_skip not applied — see point 3)



module bitsys_mac
    import bitsys_pkg::*;
(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clear,      // load first product (start new dot-product)
    input  logic               en,         // data valid — accumulate
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

    // -----------------------------------------------------------------------
    // Input sparsity detection
    // pe_skip = 1 when this PE's a operand is all-zero and BNN mode is off.
    // a_gated forces the multiplier input to zero when skipping, suppressing
    // the 64-AND partial-product array and its downstream adder switching.
    // -----------------------------------------------------------------------
    logic        pe_skip;
    logic [7:0]  a_gated;

    assign pe_skip = (~|a_in) & ~bnn_mode;
    assign a_gated = pe_skip ? 8'h00 : a_in;

    // Clock gating signals
    logic clk_accu;      // Gated clock for accumulator
    logic clk_data;      // Gated clock for data path (a_out, b_out)
    logic accu_en;       // Accumulator clock gate enable
    logic data_en;       // Data path clock gate enable

    bitsys_mul u_mul (
        .a        (a_gated),     // zero when pe_skip — suppresses AND-array switching
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

    // Accumulator clock gate.
    // clear is NOT masked by pe_skip: when a new operation starts and the
    // a-operand is zero, the clear cycle must still fire to load accu_in=0
    // (a_gated=0), resetting the accumulator from any prior computation.
    // Without this, stale results from the previous operation persist.
    // Subsequent en cycles ARE masked: adding 0 repeatedly is correctly suppressed.
    assign accu_en = clear | (en & ~pe_skip);

    bitsys_clock_gate u_clk_gate_accu (
        .clk           (clk),
        .enable        (accu_en),
        .test_enable   (1'b0),
        .gated_clk     (clk_accu)
    );

    // Data-path clock gate.
    // pe_skip is intentionally NOT applied here.  The systolic pass-through
    // registers (a_out, b_out) must always shift when en=1 so that a zero
    // value propagates to the right along the row, allowing downstream PEs
    // in the same row to independently detect their own a_in=0 and skip.
    // If data_en were gated by pe_skip, stale non-zero values from a prior
    // operation would remain in a_out and prevent downstream PEs from skipping.
    // The dominant power saving comes from the accumulator and multiplier
    // gates above; the data-path registers are small by comparison.
    assign data_en = en;

    bitsys_clock_gate u_clk_gate_data (
        .clk           (clk),
        .enable        (data_en),
        .test_enable   (1'b0),
        .gated_clk     (clk_data)
    );

    // Accumulator with gated clock
    always_ff @(posedge clk_accu or negedge rst_n) begin
        if (!rst_n) begin
            result <= 32'sd0;
        end else begin
            if (clear)
                // Load first product (clear_sr fires same cycle as first data)
                result <= 32'(signed'(accu_in));
            else if (en)
                result <= result + 32'(signed'(accu_in));
        end
    end

    // Data path with gated clock
    always_ff @(posedge clk_data or negedge rst_n) begin
        if (!rst_n) begin
            a_out  <= 8'b0;
            b_out  <= 8'b0;
        end else begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule