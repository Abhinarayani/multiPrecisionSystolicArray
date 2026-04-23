// bitsys_hps_top.sv
// Top-level with HPS integration
//
// This module:
// 1. Instantiates the Platform Designer HPS system (hps_system.sv - auto-generated from Qsys)
// 2. Connects clock and reset from FPGA to HPS
// 3. Routes UART signals from HPS to your BitSys logic
// 4. Instantiates bitsys_uart_top to handle BitSys compute operations
//
// Pin Assignments:
//   clk       → AF14 (CLOCK_50)
//   rst_n     → AE9  (KEY0, active low)
//   uart_rx   → B25  (from HPS UART receiver)
//   uart_tx   → C25  (to HPS UART transmitter)

`timescale 1ns/1ps

module bitsys_hps_top (
    input  logic clk,
    input  logic rst_n
);

    // ─────────────────────────────────────────────────────────────────────
    // HPS System Instance
    // Auto-generated from Platform Designer (Qsys)
    // The generated hps_system.sv should be in the same directory
    // ─────────────────────────────────────────────────────────────────────

    logic uart_rx;      // from HPS UART receiver (after FPGA routing)
    logic uart_tx;      // to HPS UART transmitter (after FPGA routing)
    logic [63:0] hps_io;  // HPS I/O control (auto-assigned, DO NOT manually assign)

    hps_system u_hps (
        .clk_clk                (clk),       // 50 MHz clock from FPGA
        .clk_reset_reset_n      (rst_n),     // Active-low reset from FPGA
        
        // HPS I/O ports (these handle all HPS pin multiplexing)
        .hps_io_hps_io          (hps_io),    // 64-bit control/data bus
        
        // UART signals routed to FPGA fabric
        .uart_rx                (uart_rx),   // RX from HPS (input to FPGA logic)
        .uart_tx                (uart_tx)    // TX to HPS (output from FPGA logic)
        
        // Optional: Uncomment if flow control is enabled in Qsys
        // .uart_cts               (1'b0),      // Clear-to-Send (tie low if unused)
        // .uart_rts               ()           // Request-to-Send (leave open if unused)
    );

    // ─────────────────────────────────────────────────────────────────────
    // BitSys UART Top Instance
    // Uses the UART signals from HPS (routed through FPGA fabric)
    // ─────────────────────────────────────────────────────────────────────

    bitsys_uart_top #(
        .CLK_FREQ (50_000_000),
        .BAUD     (115_200)
    ) u_bitsys (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx_pin  (uart_rx),    // from HPS UART
        .uart_tx_pin  (uart_tx)     // to HPS UART
    );

endmodule
