// bitsys_clock_gate.sv
// Integrated Clock Gating (ICG) Cell
//
// Latch-based clock gate to reduce dynamic power.
// The latch captures the enable signal on clock low, then gates it through
// when clock is high. This eliminates unnecessary clocking when disabled.
//
// Parameters:
//   enable     : 1 = clock gated through, 0 = clock held low
//   test_enable: Override for test mode (tie to 1'b0 if unused)
//
// Output:
//   gated_clk  : Gated clock (gated_clk = clk & latch_out)

module bitsys_clock_gate (
    input  logic clk,
    input  logic enable,
    input  logic test_enable,
    output logic gated_clk
);

    logic latch_out;

    // Latch captures enable on clock low
    always_latch begin
        if (~clk)
            latch_out <= enable | test_enable;
    end

    // AND gate: clock only passes when latch is high
    assign gated_clk = clk & latch_out;

endmodule
