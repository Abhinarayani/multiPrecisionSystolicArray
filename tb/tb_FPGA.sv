// tb_bitsys_uart_top.sv
// Testbench for bitsys_uart_top
//
// Simulates a PC communicating over UART with the FPGA top-level.
// Sends the same 4 matrix-multiply test cases as tb_bitsys_systolic_array.sv
// and checks the received C = A×B result against a software reference.
//
// ─── Simulation speed trick ───────────────────────────────────────────────────
//   CLK_FREQ is set to 1 MHz so that BAUD_DIV = 1_000_000/115_200 ≈ 8 cycles
//   per bit → ~90 clock cycles per UART byte.  33 bytes in + 64 bytes out
//   costs ~8,000 cycles; the whole run finishes well under 1 ms sim time.
//
// ─── Packet format (matches bitsys_uart_top.sv) ──────────────────────────────
//   PC→FPGA  33 bytes : [config] [A row-major 16 bytes] [B row-major 16 bytes]
//   FPGA→PC  64 bytes : C[0][0]…C[3][3], each 4 bytes big-endian int32

`timescale 1ns/1ps

module tb_bitsys_uart_top;
    import bitsys_pkg::*;

    // -------------------------------------------------------------------------
    // Parameters — use small CLK_FREQ to keep simulation fast
    // -------------------------------------------------------------------------
    localparam int CLK_FREQ  = 1_000_000;   // 1 MHz sim clock
    localparam int BAUD      = 115_200;
    localparam int N         = SA_SIZE;      // 4
    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;  // 1000 ns = 1 µs

    // Baud period in clock cycles (integer, matches DUT localparam)
    localparam int BAUD_DIV  = CLK_FREQ / BAUD;  // = 8

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    logic uart_rx_pin;   // TB drives this  (PC → FPGA)
    logic uart_tx_pin;   // TB monitors this (FPGA → PC)

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    bitsys_uart_top #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD),
        .N        (N)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx_pin  (uart_rx_pin),
        .uart_tx_pin  (uart_tx_pin)
    );

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Software reference: C[row][col] = sum_k A[row][k] * B[k][col]
    // -------------------------------------------------------------------------
    function automatic logic signed [31:0] ref_elem(
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1],
        input int row, col);
        logic signed [31:0] s;
        s = 0;
        for (int k = 0; k < N; k++)
            s += 32'(signed'(A[row][k])) * 32'(signed'(B[k][col]));
        return s;
    endfunction

    // -------------------------------------------------------------------------
    // Task: send one UART byte on uart_rx_pin (TB drives the line)
    //   Format: idle-high, start(0), D0..D7 LSB-first, stop(1)
    //   Each bit lasts BAUD_DIV clock cycles
    // -------------------------------------------------------------------------
    task automatic uart_send_byte(input logic [7:0] data);
        // start bit
        uart_rx_pin = 1'b0;
        repeat(BAUD_DIV) @(posedge clk);
        // 8 data bits, LSB first
        for (int b = 0; b < 8; b++) begin
            uart_rx_pin = data[b];
            repeat(BAUD_DIV) @(posedge clk);
        end
        // stop bit
        uart_rx_pin = 1'b1;
        repeat(BAUD_DIV) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Task: receive one UART byte from uart_tx_pin (TB monitors the line)
    //   Waits for falling edge (start bit), samples at mid-bit of each data bit
    // -------------------------------------------------------------------------
    task automatic uart_recv_byte(output logic [7:0] data);
        // Wait for start bit (falling edge on tx pin)
        @(negedge uart_tx_pin);
        // Skip to middle of start bit
        repeat(BAUD_DIV / 2) @(posedge clk);
        // Sample 8 data bits
        for (int b = 0; b < 8; b++) begin
            repeat(BAUD_DIV) @(posedge clk);
            data[b] = uart_tx_pin;
        end
        // Consume stop bit period
        repeat(BAUD_DIV) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Task: send a full 33-byte packet to the DUT
    //   config byte = { bnn_mode[7], is_signed[6], prec[5:4], 4'b0 }
    //   A and B are sent row-major
    // -------------------------------------------------------------------------
    task automatic send_packet(
        input logic [1:0]      prec,
        input logic            is_signed,
        input logic            bnn_mode,
        input logic signed [7:0] A [0:N-1][0:N-1],
        input logic signed [7:0] B [0:N-1][0:N-1]);

        logic [7:0] cfg;
        cfg = {bnn_mode, is_signed, prec, 4'b0};

        uart_send_byte(cfg);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                uart_send_byte(A[i][j]);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                uart_send_byte(B[i][j]);
    endtask

    // -------------------------------------------------------------------------
    // Task: receive 64-byte result packet from DUT and reconstruct C matrix
    //   Each element is 4 bytes, big-endian (MSB first)
    // -------------------------------------------------------------------------
    task automatic recv_result(output logic signed [31:0] C [0:N-1][0:N-1]);
        logic [7:0] b3, b2, b1, b0;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                uart_recv_byte(b3);
                uart_recv_byte(b2);
                uart_recv_byte(b1);
                uart_recv_byte(b0);
                C[i][j] = signed'({b3, b2, b1, b0});
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: run one full test — send packet, receive result, compare to ref
    // -------------------------------------------------------------------------
    task automatic run_test(
        input  string            test_name,
        input  logic [1:0]       prec,
        input  logic             is_signed,
        input  logic             bnn_mode,
        input  logic signed [7:0] A [0:N-1][0:N-1],
        input  logic signed [7:0] B [0:N-1][0:N-1]);

        logic signed [31:0] C_dut [0:N-1][0:N-1];
        logic signed [31:0] C_ref [0:N-1][0:N-1];
        int errors;

        // Compute software reference
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                C_ref[i][j] = ref_elem(A, B, i, j);

        // Send packet to DUT over UART
        send_packet(prec, is_signed, bnn_mode, A, B);

        // Receive result from DUT over UART
        recv_result(C_dut);

        // Compare
        errors = 0;
        $display("\n--- %s ---", test_name);
        $display("  Expected C:");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) $write("%8d ", C_ref[i][j]);
            $display("");
        end
        $display("  DUT C (via UART):");
        for (int i = 0; i < N; i++) begin
            $write("  ");
            for (int j = 0; j < N; j++) begin
                $write("%8d ", C_dut[i][j]);
                if (C_dut[i][j] !== C_ref[i][j]) errors++;
            end
            $display("");
        end
        if (errors == 0)
            $display("  PASS – all %0d elements correct", N*N);
        else
            $display("  FAIL – %0d mismatches", errors);

    endtask

    // -------------------------------------------------------------------------
    // Test matrices (identical to tb_bitsys_systolic_array.sv)
    // -------------------------------------------------------------------------
    logic signed [7:0] A_I [0:N-1][0:N-1];   // Identity
    logic signed [7:0] B1  [0:N-1][0:N-1];
    logic signed [7:0] A2  [0:N-1][0:N-1];
    logic signed [7:0] B2  [0:N-1][0:N-1];
    logic signed [7:0] A3  [0:N-1][0:N-1];
    logic signed [7:0] B3  [0:N-1][0:N-1];
    logic signed [7:0] A4  [0:N-1][0:N-1];   // Extreme values
    logic signed [7:0] B4  [0:N-1][0:N-1];

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // --- idle line high, reset ---
        uart_rx_pin = 1'b1;
        rst_n       = 1'b0;
        repeat(8) @(negedge clk);
        rst_n = 1'b1;
        repeat(4) @(negedge clk);

        // --- Build test matrices ---

        // Identity
        A_I = '{default:'0};
        for (int k = 0; k < N; k++) A_I[k][k] = 8'sd1;

        B1 = '{'{8'sd1,  8'sd2,  8'sd3,  8'sd4},
               '{8'sd5,  8'sd6,  8'sd7,  8'sd8},
               '{8'sd9,  8'sd10, 8'sd11, 8'sd12},
               '{8'sd13, 8'sd14, 8'sd15, 8'sd16}};

        A2 = '{'{8'sd1, 8'sd2, 8'sd3, 8'sd4},
               '{8'sd5, 8'sd6, 8'sd7, 8'sd8},
               '{8'sd2, 8'sd1, 8'sd4, 8'sd3},
               '{8'sd4, 8'sd3, 8'sd2, 8'sd1}};
        B2 = '{'{8'sd1, 8'sd0, 8'sd0, 8'sd1},
               '{8'sd0, 8'sd1, 8'sd1, 8'sd0},
               '{8'sd2, 8'sd2, 8'sd0, 8'sd0},
               '{8'sd0, 8'sd0, 8'sd3, 8'sd3}};

        A3 = '{'{8'sd3,   -8'sd2,  8'sd1,  -8'sd4},
               '{-8'sd5,  8'sd6,  -8'sd7,   8'sd8},
               '{8'sd9,   -8'sd10, 8'sd11, -8'sd12},
               '{-8'sd13, 8'sd14, -8'sd15,  8'sd16}};
        B3 = '{'{8'sd2,   -8'sd1,  8'sd3,  -8'sd2},
               '{-8'sd4,  8'sd5,  -8'sd6,   8'sd7},
               '{8'sd8,   -8'sd9,  8'sd10, -8'sd11},
               '{-8'sd12, 8'sd13, -8'sd14,  8'sd15}};

        A4 = '{'{-8'sd128, -8'sd128, -8'sd128, -8'sd128},
               '{ 8'sd127,  8'sd127,  8'sd127,  8'sd127},
               '{-8'sd1,    8'sd1,   -8'sd1,    8'sd1},
               '{ 8'sd0,    8'sd0,    8'sd0,    8'sd0}};
        B4 = '{'{8'sd1, 8'sd0, 8'sd0, 8'sd0},
               '{8'sd0, 8'sd1, 8'sd0, 8'sd0},
               '{8'sd0, 8'sd0, 8'sd1, 8'sd0},
               '{8'sd0, 8'sd0, 8'sd0, 8'sd1}};

        $display("\n=====================================================");
        $display("  UART Top-Level TB  (CLK=%0d Hz, BAUD=%0d, N=%0d)",
                 CLK_FREQ, BAUD, N);
        $display("=====================================================");

        // PREC_8B = 2'b11, is_signed=1, bnn_mode=0 for all four tests
        run_test("Test 1: Identity × B1",    PREC_8B, 1'b1, 1'b0, A_I, B1);
        run_test("Test 2: Positive integers", PREC_8B, 1'b1, 1'b0, A2,  B2);
        run_test("Test 3: Mixed sign",        PREC_8B, 1'b1, 1'b0, A3,  B3);
        run_test("Test 4: Extreme values",    PREC_8B, 1'b1, 1'b0, A4,  B4);

        $display("\n========= All UART tests complete =========\n");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog — generous timeout: 33+64 bytes × 11 bits × BAUD_DIV cycles
    //   × 4 tests + overhead × 2 safety margin
    // -------------------------------------------------------------------------
    localparam int WATCHDOG_CYCLES = 4 * (33 + 64) * 11 * BAUD_DIV * 3;

    initial begin
        #(WATCHDOG_CYCLES * CLK_PERIOD_NS);
        $display("TIMEOUT: simulation exceeded %0d cycles", WATCHDOG_CYCLES);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Optional: waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_bitsys_uart_top.vcd");
        $dumpvars(0, tb_bitsys_uart_top);
    end

endmodule