// bitsys_de1_top.sv
// Top-level wrapper integrating HPS system with BitSys UART logic
//
// This module:
// 1. Instantiates the Qsys-generated de1 HPS system
// 2. Instantiates bitsys_uart_top for BitSys compute logic
// 3. Connects HPS UART signals to BitSys UART interface
//
// Pin Assignments:
//   clk   → AF14 (CLOCK_50, from FPGA)
//   rst_n → AE9  (KEY0, active low)
//   UART RX/TX → Handled by HPS on pins B25/C25



module bitsys_de1_top (
    input  logic clk,
    input  logic rst_n,
    input  logic uart0_rxd,    // HPS UART0 RX (from external pin B25)
    output logic uart0_txd     // HPS UART0 TX (to external pin C25)
);

    // ─────────────────────────────────────────────────────────────────────
    // HPS System Instance
    // Generated from Qsys (de1.qsys)
    // Provides: UART0 (pins B25/C25), SDRAM, clock/reset management
    // ─────────────────────────────────────────────────────────────────────

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
        
        // UART0 signals (primary UART for BitSys communication)
        .hps_0_uart0_cts            (1'b0),          // Clear-to-Send (tie low if not used)
        .hps_0_uart0_dsr            (1'b0),          // Data Set Ready
        .hps_0_uart0_dcd            (1'b0),          // Data Carrier Detect
        .hps_0_uart0_ri             (1'b0),          // Ring Indicator
        .hps_0_uart0_dtr            (),              // Data Terminal Ready (output)
        .hps_0_uart0_rts            (),              // Request to Send (output)
        .hps_0_uart0_out1_n         (),              // Output 1 (modem control)
        .hps_0_uart0_out2_n         (),              // Output 2 (modem control)
        .hps_0_uart0_rxd            (uart0_rxd),     // UART0 RX data (INPUT)
        .hps_0_uart0_txd            (uart0_txd),     // UART0 TX data (OUTPUT)
        
        // UART1 signals (optional, not used)
        .hps_0_uart1_cts            (1'b0),
        .hps_0_uart1_dsr            (1'b0),
        .hps_0_uart1_dcd            (1'b0),
        .hps_0_uart1_ri             (1'b0),
        .hps_0_uart1_dtr            (),
        .hps_0_uart1_rts            (),
        .hps_0_uart1_out1_n         (),
        .hps_0_uart1_out2_n         (),
        .hps_0_uart1_rxd            (1'b0),          // Not used
        .hps_0_uart1_txd            ()               // Not used
    );

    // ─────────────────────────────────────────────────────────────────────
    // BitSys UART Top Instance
    // Uses HPS UART signals routed through FPGA fabric
    // ─────────────────────────────────────────────────────────────────────

    bitsys_uart_top #(
        .CLK_FREQ (50_000_000),
        .BAUD     (115_200)
    ) u_bitsys (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx_pin  (uart0_rxd),   // from HPS UART0 RX
        .uart_tx_pin  (uart0_txd)    // to HPS UART0 TX
    );

endmodule
