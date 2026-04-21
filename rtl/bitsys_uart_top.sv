// bitsys_uart_top.sv
// Top-level wrapper: BitSys Systolic Array with UART Interface
//
// Data Protocol:
//   Host sends matrix A and B in row-major order (4x4 = 16 bytes each)
//   FPGA computes C = A × B and sends results back (32-bit per element)
//
// Command Format:
//   CMD=0x01: Start new matrix multiplication
//   CMD=0x02: Send A matrix data
//   CMD=0x03: Send B matrix data
//   CMD=0x04: Request results
//
// Baud rate: 115200 (standard)
// Clock: 50 MHz (DE1-SoC CLOCK_50)

`include "bitsys_pkg.sv"

module bitsys_uart_top
    import bitsys_pkg::*;
(
    input  logic            clk,           // 50 MHz clock
    input  logic            rst_n,
    input  logic            rx,            // UART RX line
    output logic            tx,            // UART TX line
    input  logic [1:0]      prec,          // Precision mode (via GPIO or hardcoded)
    input  logic            is_signed,     // Signed mode (via GPIO or hardcoded)
    input  logic            bnn_mode       // BNN mode (via GPIO or hardcoded)
);

    // -----------------------------------------------------------------------
    // Clock generation for UART (115200 baud @ 50 MHz)
    // baud_count = 50_000_000 / (115200 * 16) ≈ 27
    // Using 27 for ~115470 baud (0.2% error, acceptable)
    // -----------------------------------------------------------------------
    localparam int BAUD_COUNT = 27;

    // -----------------------------------------------------------------------
    // Control and data registers
    // -----------------------------------------------------------------------
    logic [7:0]  uart_rx_data;
    logic        uart_rx_valid;
    logic [7:0]  uart_tx_data;
    logic        uart_tx_send;
    logic        uart_tx_busy;

    logic [7:0]  a_matrix [0:15];  // 4×4 matrix A
    logic [7:0]  b_matrix [0:15];  // 4×4 matrix B
    logic        sa_start;
    logic        sa_output_valid;
    logic signed [31:0] sa_result [0:3][0:3];  // 4×4 result matrix

    logic [4:0]  rx_byte_count;    // Count of bytes received
    logic [1:0]  rx_state;         // Receiving state: 0=idle, 1=A matrix, 2=B matrix
    logic [3:0]  result_idx;       // Current result being transmitted
    logic        sending_results;

    // -----------------------------------------------------------------------
    // UART RX
    // -----------------------------------------------------------------------
    uart_rx u_uart_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx          (rx),
        .baud_count  (BAUD_COUNT),
        .data        (uart_rx_data),
        .data_valid  (uart_rx_valid),
        .busy        ()
    );

    // -----------------------------------------------------------------------
    // UART TX
    // -----------------------------------------------------------------------
    uart_tx u_uart_tx (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_in     (uart_tx_data),
        .send        (uart_tx_send),
        .baud_count  (BAUD_COUNT),
        .tx          (tx),
        .busy        (uart_tx_busy)
    );

    // -----------------------------------------------------------------------
    // BitSys Systolic Array Instance (N=4)
    // -----------------------------------------------------------------------
    bitsys_systolic_array #(.N(4)) u_sa (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (sa_start),
        .prec          (prec),
        .is_signed     (is_signed),
        .bnn_mode      (bnn_mode),
        .a_in          (a_matrix[0:3]),
        .b_in          (b_matrix[0:3]),
        .output_valid  (sa_output_valid),
        .c_out         (sa_result)
    );

    // -----------------------------------------------------------------------
    // RX Control State Machine
    // Receives commands and matrix data from host
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= 2'b00;
            rx_byte_count <= '0;
            sa_start <= 1'b0;
        end else begin
            sa_start <= 1'b0;  // One-cycle pulse

            if (uart_rx_valid) begin
                case (uart_rx_data)
                    8'h01: begin
                        // CMD 0x01: Start multiplication
                        sa_start <= 1'b1;
                        rx_state <= 2'b00;
                        rx_byte_count <= '0;
                    end

                    8'h02: begin
                        // CMD 0x02: Start receiving A matrix
                        rx_state <= 2'b01;
                        rx_byte_count <= '0;
                    end

                    8'h03: begin
                        // CMD 0x03: Start receiving B matrix
                        rx_state <= 2'b10;
                        rx_byte_count <= '0;
                    end

                    8'h04: begin
                        // CMD 0x04: Request results
                        sending_results <= 1'b1;
                        result_idx <= '0;
                    end

                    default: begin
                        // Data byte: store in appropriate matrix
                        case (rx_state)
                            2'b01: begin
                                // Receiving A matrix
                                if (rx_byte_count < 16) begin
                                    a_matrix[rx_byte_count] <= uart_rx_data;
                                    rx_byte_count <= rx_byte_count + 1;
                                end
                            end

                            2'b10: begin
                                // Receiving B matrix
                                if (rx_byte_count < 16) begin
                                    b_matrix[rx_byte_count] <= uart_rx_data;
                                    rx_byte_count <= rx_byte_count + 1;
                                end
                            end

                            default: begin
                            end
                        endcase
                    end
                endcase
            end
        end
    end

    // -----------------------------------------------------------------------
    // TX Control State Machine
    // Transmits results back to host
    // Format: 4 bytes per result (32-bit signed integer, big-endian)
    // -----------------------------------------------------------------------
    logic [2:0]  tx_byte_idx;      // Which byte of the 32-bit result

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_send <= 1'b0;
            uart_tx_data <= '0;
            sending_results <= 1'b0;
            result_idx <= '0;
            tx_byte_idx <= '0;
        end else begin
            uart_tx_send <= 1'b0;

            if (sending_results && !uart_tx_busy) begin
                // Calculate row and column from result_idx
                logic [2:0] row, col;
                row = result_idx[3:2];
                col = result_idx[1:0];

                // Send bytes in big-endian order
                case (tx_byte_idx)
                    3'h0: uart_tx_data <= sa_result[row][col][31:24];
                    3'h1: uart_tx_data <= sa_result[row][col][23:16];
                    3'h2: uart_tx_data <= sa_result[row][col][15:8];
                    3'h3: uart_tx_data <= sa_result[row][col][7:0];
                    default: uart_tx_data <= '0;
                endcase

                uart_tx_send <= 1'b1;
                tx_byte_idx <= tx_byte_idx + 1;

                // Move to next result after sending all 4 bytes
                if (tx_byte_idx == 3'h3) begin
                    result_idx <= result_idx + 1;
                    tx_byte_idx <= '0;

                    // Done after sending all 16 results (4×4)
                    if (result_idx == 4'hF) begin
                        sending_results <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
