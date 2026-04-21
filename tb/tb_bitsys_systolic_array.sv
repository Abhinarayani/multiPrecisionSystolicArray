// tb_bitsys_systolic_array.sv
// Testbench for bitsys_systolic_array – 8-bit signed matrix multiplication

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

module tb_bitsys_systolic_array;
    import bitsys_pkg::*;

    localparam int N   = 4;
    localparam int CLK = 10;

    logic            clk, rst_n, start;
    logic [1:0]      prec;
    logic            is_signed, bnn_mode;
    logic [7:0]      a_in [0:N-1];
    logic [7:0]      b_in [0:N-1];
    logic            output_valid;
    logic signed [31:0] c_out [0:N-1][0:N-1];

    bitsys_systolic_array #(.N(N)) dut (.*);

    initial clk = 0;
    always #(CLK/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // Software reference C = A×B (signed 32-bit)
    // -----------------------------------------------------------------------
    function automatic logic signed [31:0] ref_c_elem(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1],
        input int row, col);
        logic signed [31:0] s = 0;
        for (int k = 0; k < N; k++)
            s += 32'(A[row][k]) * 32'(B[k][col]);
        return s;
    endfunction

    // -----------------------------------------------------------------------
    // Task: run one matrix multiplication and verify
    // Feeds A columns and B rows sequentially, one per clock cycle.
    // -----------------------------------------------------------------------
    task automatic run_matmul(
        input  string              test_name,
        input  logic signed [7:0]  A [0:N-1][0:N-1],
        input  logic signed [7:0]  B [0:N-1][0:N-1]);

        logic signed [31:0] expected [0:N-1][0:N-1];
        int errors;

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                expected[i][j] = ref_c_elem(A, B, i, j);

        // --- Feed data ---
        // Cycle 0: start=1, feed k=0 column of A and row 0 of B
        @(negedge clk);
        start = 1;
        for (int i = 0; i < N; i++) a_in[i] = A[i][0];
        for (int j = 0; j < N; j++) b_in[j] = B[0][j];

        // Cycles 1..N-1: feed remaining columns/rows
        for (int k = 1; k < N; k++) begin
            @(negedge clk);
            start = 0;
            for (int i = 0; i < N; i++) a_in[i] = A[i][k];
            for (int j = 0; j < N; j++) b_in[j] = B[k][j];
        end

        // Zero inputs (pipeline drain)
        @(negedge clk);
        start = 0;
        for (int i = 0; i < N; i++) a_in[i] = 8'b0;
        for (int j = 0; j < N; j++) b_in[j] = 8'b0;

        // Wait for output_valid
        @(posedge output_valid);
        @(negedge clk);  // settle

        // --- Check results ---
        errors = 0;
        $display("\n--- %s ---", test_name);
        $display("  Expected C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) $write("%8d ", expected[i][j]);
            $display("");
        end
        $display("  DUT C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%8d ", c_out[i][j]);
                if (c_out[i][j] !== expected[i][j]) errors++;
            end
            $display("");
        end
        if (errors == 0)
            $display("  PASS – all %0d elements correct", N*N);
        else
            $display("  FAIL – %0d mismatches", errors);

        repeat(3) @(negedge clk);
    endtask

    // -----------------------------------------------------------------------
    // Test matrices
    // -----------------------------------------------------------------------
    logic signed [7:0] A_I [0:N-1][0:N-1];   // Identity
    logic signed [7:0] B1  [0:N-1][0:N-1];   // Simple ints
    logic signed [7:0] A2  [0:N-1][0:N-1];
    logic signed [7:0] B2  [0:N-1][0:N-1];
    logic signed [7:0] A3  [0:N-1][0:N-1];   // Mixed sign
    logic signed [7:0] B3  [0:N-1][0:N-1];
    logic signed [7:0] A4  [0:N-1][0:N-1];   // Corner: all -128/127
    logic signed [7:0] B4  [0:N-1][0:N-1];

    initial begin
        // Identity
        A_I = '{default:'0};
        for (int k = 0; k < N; k++) A_I[k][k] = 8'sd1;

        B1  = '{'{8'sd1, 8'sd2,  8'sd3,  8'sd4},
                '{8'sd5, 8'sd6,  8'sd7,  8'sd8},
                '{8'sd9, 8'sd10, 8'sd11, 8'sd12},
                '{8'sd13,8'sd14, 8'sd15, 8'sd16}};

        A2  = '{'{8'sd1,8'sd2,8'sd3,8'sd4},
                '{8'sd5,8'sd6,8'sd7,8'sd8},  // values ≤8 fit in 8-bit signed
                '{8'sd2,8'sd1,8'sd4,8'sd3},
                '{8'sd4,8'sd3,8'sd2,8'sd1}};
        B2  = '{'{8'sd1,8'sd0,8'sd0,8'sd1},
                '{8'sd0,8'sd1,8'sd1,8'sd0},
                '{8'sd2,8'sd2,8'sd0,8'sd0},
                '{8'sd0,8'sd0,8'sd3,8'sd3}};

        A3  = '{'{8'sd3,  -8'sd2,  8'sd1, -8'sd4},
                '{-8'sd5,  8'sd6, -8'sd7,  8'sd8},
                '{8'sd9,  -8'sd10, 8'sd11,-8'sd12},
                '{-8'sd13, 8'sd14,-8'sd15, 8'sd16}};
        B3  = '{'{8'sd2,  -8'sd1,  8'sd3, -8'sd2},
                '{-8'sd4,  8'sd5, -8'sd6,  8'sd7},
                '{8'sd8,  -8'sd9,  8'sd10,-8'sd11},
                '{-8'sd12, 8'sd13,-8'sd14, 8'sd15}};

        // Corner cases: extreme values
        A4  = '{'{-8'sd128,-8'sd128,-8'sd128,-8'sd128},
                '{ 8'sd127, 8'sd127, 8'sd127, 8'sd127},
                '{-8'sd1,   8'sd1,  -8'sd1,   8'sd1},
                '{ 8'sd0,   8'sd0,   8'sd0,   8'sd0}};
        B4  = '{'{8'sd1, 8'sd0, 8'sd0, 8'sd0},
                '{8'sd0, 8'sd1, 8'sd0, 8'sd0},
                '{8'sd0, 8'sd0, 8'sd1, 8'sd0},
                '{8'sd0, 8'sd0, 8'sd0, 8'sd1}};
    end

    initial begin
        rst_n = 0; start = 0; prec = PREC_8B; is_signed = 1; bnn_mode = 0;
        for (int i = 0; i < N; i++) begin a_in[i] = 0; b_in[i] = 0; end
        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        $display("\n=========================================");
        $display("  BitSys Systolic Array TB  (N=%0d, 8b)", N);
        $display("=========================================");

        run_matmul("Test 1: Identity × B1",    A_I, B1);
        run_matmul("Test 2: Positive integers", A2,  B2);
        run_matmul("Test 3: Mixed sign",        A3,  B3);
        run_matmul("Test 4: Extreme values",    A4,  B4);

        $display("\n========= All tests complete =========\n");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
