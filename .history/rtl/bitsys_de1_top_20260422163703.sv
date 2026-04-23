// bitsys_de1_top.sv
// Top-level wrapper integrating HPS system with BitSys UART logic
//
// This module:
// 1. Instantiates the Qsys-generated de1 HPS system
// 2. Instantiates bitsys_uart_top for BitSys compute logic
// 3. Routes UART through HPS pins B25/C25 to BitSys
//
// Architecture:
//   External RX → B25 (HPS pin) → hps_0_uart0_rxd → BitSys UART RX
//   BitSys UART TX → hps_0_uart0_txd → C25 (HPS pin) → External TX
//
// Pin Assignments:
//   clk   → AF14 (CLOCK_50, from FPGA)
//   rst_n → AE9  (KEY0, active low)
//   UART RX → B25 (HPS UART0, automatic)
//   UART TX → C25 (HPS UART0, automatic)



module bitsys_de1_top (
    input  logic clk,
    input  logic rst_n
);

    // ─────────────────────────────────────────────────────────────────────
    // Internal UART signals: routed through HPS to B25/C25
    // ─────────────────────────────────────────────────────────────────────

    logic uart_rx_internal;       // RX from B25 (HPS UART0 RX to FPGA)
    logic uart_tx_internal;       // TX to C25 (FPGA to HPS UART0 TX)

    // ─────────────────────────────────────────────────────────────────────
    // HPS System Instance
    // Generated from Qsys (de1.qsys)
    // Provides: UART0 (routed to FPGA fabric), SDRAM, clock/reset management
    //
    // NOTE: BitSys UART (not HPS UART) controls external pins B25/C25
    //       HPS UART signals are not used for external I/O
    // ─────────────────────────────────────────────────────────────────────

    logic hps_uart0_txd;  // Unused output from HPS (left floating)

    de1 u_hps (
        .clk_clk                    (clk),
        .memory_mem_a               (),              // SDRAM address (unconnected for now)
        .memory_mem_ba              (),              // SDRAM bank address
        .memory_mem_ck              (),              // SDRAM clock
        .memory_mem_ck_n            (),              // SDRAM clock (inverted)
        .memory_mem_cke             (),              // SDRAM clock enable
        .memory_mem_cs_n            (),              // SDRAM chip select
        .memory_mem_ras_n           (),              // SDRAM RAS
        .memory_mem_cas_n           (),              // SDRAM CAS
        .memory_mem_we_n            (),              // SDRAM write enable
        .memory_mem_reset_n         (),              // SDRAM reset
        .memory_mem_dq              (),              // SDRAM data
        .memory_mem_dqs             (),              // SDRAM DQS
        .memory_mem_dqs_n           (),              // SDRAM DQS (inverted)
        .memory_mem_odt             (),              // SDRAM ODT
        .memory_mem_dm              (),              // SDRAM DM
        .memory_oct_rzqin           (1'b0),          // SDRAM OCT calibration (tie low)
        .hps_0_h2f_gp_gp_in         (32'b0),         // HPS-to-FPGA GP input (unused)
        .hps_0_h2f_gp_gp_out        (),              // HPS-to-FPGA GP output (unused)
        
        // UART0 signals (routed to FPGA but not used for external I/O)
        .hps_0_uart0_cts            (1'b0),          // Clear-to-Send (tie low)
        .hps_0_uart0_dsr            (1'b0),          // Data Set Ready
        .hps_0_uart0_dcd            (1'b0),          // Data Carrier Detect
        .hps_0_uart0_ri             (1'b0),          // Ring Indicator
        .hps_0_uart0_dtr            (),              // Data Terminal Ready
        .hps_0_uart0_rts            (),              // Request to Send
        .hps_0_uart0_out1_n         (),              // Output 1 (modem control)
        .hps_0_uart0_out2_n         (),              // Output 2 (modem control)
        .hps_0_uart0_rxd            (uart_rx),       // Connect external RX for HPS (unused, but required)
        .hps_0_uart0_txd            (hps_uart0_txd), // HPS TX output (unused; left floating)
        
        // UART1 signals (not used)
        .hps_0_uart1_cts            (1'b0),
        .hps_0_uart1_dsr            (1'b0),
        .hps_0_uart1_dcd            (1'b0),
        .hps_0_uart1_ri             (1'b0),
        .hps_0_uart1_dtr            (),
        .hps_0_uart1_rts            (),
        .hps_0_uart1_out1_n         (),
        .hps_0_uart1_out2_n         (),
        .hps_0_uart1_rxd            (1'b0),
        .hps_0_uart1_txd            ()
    );

    // ─────────────────────────────────────────────────────────────────────
    // BitSys UART Controller
    // Handles external UART communication on pins B25 (RX) and C25 (TX)
    // ─────────────────────────────────────────────────────────────────────

    bitsys_uart_top #(
        .CLK_FREQ (50_000_000),
        .BAUD     (115_200)
    ) u_bitsys (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx_pin  (uart_rx),     // Receive from external pin B25
        .uart_tx_pin  (uart_tx)      // Transmit to external pin C25
    );

endmodule
