// tb_bitsys_mul.sv
// Testbench for bitsys_mul – exhaustive spot-checks across all precision modes

`timescale 1ns/1ps
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

module tb_bitsys_mul;
    import bitsys_pkg::*;

    logic [7:0]  a, b;
    logic [1:0]  prec;
    logic        is_signed, bnn_mode;
    logic [15:0] product;

    bitsys_mul dut (.*);

    // Reference computation
    function automatic logic signed [31:0] ref_mul_signed(
        input logic signed [7:0] x, input logic signed [7:0] y);
        return 32'(x) * 32'(y);
    endfunction

    function automatic logic [31:0] ref_mul_unsigned(
        input logic [7:0] x, input logic [7:0] y);
        return {16'b0, x} * {16'b0, y};
    endfunction

    // Check single 8-bit test
    task automatic check_8b(
        input logic signed [7:0] ta,
        input logic signed [7:0] tb_v,
        input logic sig);
        logic signed [15:0] expected;
        a = ta; b = tb_v; prec = PREC_8B; is_signed = sig; bnn_mode = 0;
        #1;
        expected = sig ? 16'(ref_mul_signed(ta, tb_v))
                       : 16'(ref_mul_unsigned(ta, tb_v));
        if (product !== expected)
            $display("FAIL 8b sig=%0b a=%0d b=%0d  got=%0d exp=%0d",
                     sig, $signed(ta), $signed(tb_v), $signed(product), $signed(expected));
        else
            $display("PASS 8b sig=%0b a=%4d b=%4d  prod=%6d",
                     sig, $signed(ta), $signed(tb_v), $signed(product));
    endtask

    // Check two 4-bit channels
    task automatic check_4b(
        input logic signed [3:0] a0, b0, a1, b1,
        input logic sig);
        logic signed [7:0]  e0, e1;
        logic        [15:0] expected;
        a = {a1, a0}; b = {b1, b0};
        prec = PREC_4B; is_signed = sig; bnn_mode = 0;
        #1;
        e0 = sig ? 8'(signed'(a0)*signed'(b0)) : 8'({4'b0,a0}*{4'b0,b0});
        e1 = sig ? 8'(signed'(a1)*signed'(b1)) : 8'({4'b0,a1}*{4'b0,b1});
        expected = {e1, e0};
        if (product !== expected)
            $display("FAIL 4b sig=%0b a0=%0d b0=%0d a1=%0d b1=%0d  got=%4h exp=%4h",
                     sig, $signed(a0),$signed(b0),$signed(a1),$signed(b1),
                     product, expected);
        else
            $display("PASS 4b sig=%0b [%4d×%4d | %4d×%4d] = [%4d | %4d]",
                     sig,$signed(a0),$signed(b0),$signed(a1),$signed(b1),
                     $signed(e0),$signed(e1));
    endtask

    // Check four 2-bit channels
    task automatic check_2b(
        input logic signed [1:0] a0,b0,a1,b1,a2,b2,a3,b3,
        input logic sig);
        logic signed [3:0] e [0:3];
        logic        [15:0] expected;
        a = {a3,a2,a1,a0}; b = {b3,b2,b1,b0};
        prec = PREC_2B; is_signed = sig; bnn_mode = 0;
        #1;
        e[0] = sig ? 4'(signed'(a0)*signed'(b0)) : 4'({2'b0,a0}*{2'b0,b0});
        e[1] = sig ? 4'(signed'(a1)*signed'(b1)) : 4'({2'b0,a1}*{2'b0,b1});
        e[2] = sig ? 4'(signed'(a2)*signed'(b2)) : 4'({2'b0,a2}*{2'b0,b2});
        e[3] = sig ? 4'(signed'(a3)*signed'(b3)) : 4'({2'b0,a3}*{2'b0,b3});
        expected = {e[3],e[2],e[1],e[0]};
        if (product !== expected)
            $display("FAIL 2b got=%4h exp=%4h", product, expected);
        else
            $display("PASS 2b sig=%0b [%2d×%2d|%2d×%2d|%2d×%2d|%2d×%2d]=[%2d|%2d|%2d|%2d]",
                     sig,$signed(a0),$signed(b0),$signed(a1),$signed(b1),
                     $signed(a2),$signed(b2),$signed(a3),$signed(b3),
                     $signed(e[0]),$signed(e[1]),$signed(e[2]),$signed(e[3]));
    endtask

    // Check 8 XNOR BNN channels
    task automatic check_1b_bnn();
        logic [7:0] ta, tb_v;
        logic signed [1:0] expected_ch [0:7];
        ta = 8'b1010_0110; tb_v = 8'b0111_1001;
        a = ta; b = tb_v; prec = PREC_1B; is_signed = 1; bnn_mode = 1;
        #1;
        for (int k = 0; k < 8; k++) begin
            expected_ch[k] = (~(ta[k] ^ tb_v[k])) ? 2'sb01 : 2'sb11;
            if ($signed(product[2*k +: 2]) !== expected_ch[k])
                $display("FAIL BNN ch%0d: got=%2b exp=%2b",
                         k, product[2*k+:2], expected_ch[k]);
            else
                $display("PASS BNN ch%0d: XNOR(%0b,%0b)=%0d",
                         k, ta[k], tb_v[k], $signed(expected_ch[k]));
        end
    endtask

    initial begin
        $display("\n=== BitSys Multiplier Testbench ===\n");

        // --- 8-bit unsigned tests ---
        $display("-- 8-bit unsigned --");
        check_8b(8'd5,    8'd3,    0);
        check_8b(8'd127,  8'd127,  0);
        check_8b(8'd255,  8'd255,  0);
        check_8b(8'd0,    8'd100,  0);

        check_8b(8'd25,    8'd31,    0);
        check_8b(8'd0,  8'd0,  0);
        check_8b(8'd255,  8'd255,  0);
        check_8b(8'd111,    8'd11,  0);
        // --- 8-bit signed tests ---
        $display("\n-- 8-bit signed --");
        check_8b(-8'sd128,  -8'sd1,   1);   // -128 × -1 = 128
        check_8b(-8'sd1,    -8'sd1,   1);   // -1 × -1   = 1
        check_8b(-8'sd5,     8'sd3,   1);   // -5 × 3    = -15
        check_8b( 8'sd127,   8'sd127, 1);   // 127 × 127 = 16129
        check_8b(-8'sd128,   8'sd127, 1);   // -128 × 127 = -16256

        // --- 4-bit signed tests ---
        $display("\n-- 4-bit signed (2 channels) --");
        check_4b(-4'sd8,  -4'sd8,   4'sd7,  4'sd3, 1);
        check_4b( 4'sd5,   4'sd3,  -4'sd4,  4'sd4, 1);
        check_4b( 4'sd7,   4'sd7,   4'sd7,  4'sd7, 1);

        // --- 4-bit unsigned tests ---
        $display("\n-- 4-bit unsigned (2 channels) --");
        check_4b(4'd15, 4'd15, 4'd8, 4'd8, 0);

        // --- 2-bit signed tests ---
        $display("\n-- 2-bit signed (4 channels) --");
        check_2b(-2'sd2,-2'sd2, -2'sd1,2'sd1, 2'sd1,-2'sd2, 2'sd0,2'sd1, 1);

        // --- BNN XNOR 1-bit tests ---
        $display("\n-- 1-bit XNOR BNN mode --");
        check_1b_bnn();

        $display("\n=== Done ===\n");
        $finish;
    end

endmodule
