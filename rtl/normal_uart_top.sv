// normal_uart_top.sv
// Same UART shell as BitSys, but with a conventional 8-bit systolic core.

`include "bitsys_pkg.sv"

module normal_uart_top
    import bitsys_pkg::*;
(
    input  logic            clk,
    input  logic            rst_n,
    input  logic            rx,
    output logic            tx,
    input  logic [1:0]      prec,
    input  logic            is_signed,
    input  logic            bnn_mode
);
    localparam int BAUD_COUNT = 27;

    logic [7:0]  uart_rx_data;
    logic        uart_rx_valid;
    logic [7:0]  uart_tx_data;
    logic        uart_tx_send;
    logic        uart_tx_busy;

    logic [7:0]  a_matrix [0:15];
    logic [7:0]  b_matrix [0:15];
    logic        sa_start;
    logic        sa_output_valid;
    logic signed [31:0] sa_result [0:3][0:3];

    logic [4:0]  rx_byte_count;
    logic [1:0]  rx_state;
    logic [3:0]  result_idx;
    logic        sending_results;
    logic [2:0]  tx_byte_idx;

    uart_rx u_uart_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (rx),
        .baud_count (BAUD_COUNT),
        .data       (uart_rx_data),
        .data_valid (uart_rx_valid),
        .busy       ()
    );

    uart_tx u_uart_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_in    (uart_tx_data),
        .send       (uart_tx_send),
        .baud_count (BAUD_COUNT),
        .tx         (tx),
        .busy       (uart_tx_busy)
    );

    normal_systolic_array #(.N(4)) u_sa (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (sa_start),
        .prec         (prec),
        .is_signed    (is_signed),
        .bnn_mode     (bnn_mode),
        .a_in         (a_matrix[0:3]),
        .b_in         (b_matrix[0:3]),
        .output_valid (sa_output_valid),
        .c_out        (sa_result)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= 2'b00;
            rx_byte_count <= '0;
            sa_start <= 1'b0;
            sending_results <= 1'b0;
            result_idx <= '0;
        end else begin
            sa_start <= 1'b0;

            if (uart_rx_valid) begin
                case (uart_rx_data)
                    8'h01: begin
                        sa_start <= 1'b1;
                        rx_state <= 2'b00;
                        rx_byte_count <= '0;
                    end
                    8'h02: begin
                        rx_state <= 2'b01;
                        rx_byte_count <= '0;
                    end
                    8'h03: begin
                        rx_state <= 2'b10;
                        rx_byte_count <= '0;
                    end
                    8'h04: begin
                        sending_results <= 1'b1;
                        result_idx <= '0;
                    end
                    default: begin
                        case (rx_state)
                            2'b01: if (rx_byte_count < 16) begin
                                a_matrix[rx_byte_count] <= uart_rx_data;
                                rx_byte_count <= rx_byte_count + 1;
                            end
                            2'b10: if (rx_byte_count < 16) begin
                                b_matrix[rx_byte_count] <= uart_rx_data;
                                rx_byte_count <= rx_byte_count + 1;
                            end
                            default: begin end
                        endcase
                    end
                endcase
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_send <= 1'b0;
            uart_tx_data <= '0;
            tx_byte_idx <= '0;
        end else begin
            uart_tx_send <= 1'b0;

            if (sending_results && !uart_tx_busy) begin
                logic [2:0] row;
                logic [2:0] col;
                row = result_idx[3:2];
                col = result_idx[1:0];

                case (tx_byte_idx)
                    3'h0: uart_tx_data <= sa_result[row][col][31:24];
                    3'h1: uart_tx_data <= sa_result[row][col][23:16];
                    3'h2: uart_tx_data <= sa_result[row][col][15:8];
                    3'h3: uart_tx_data <= sa_result[row][col][7:0];
                    default: uart_tx_data <= '0;
                endcase

                uart_tx_send <= 1'b1;
                tx_byte_idx <= tx_byte_idx + 1;

                if (tx_byte_idx == 3'h3) begin
                    result_idx <= result_idx + 1;
                    tx_byte_idx <= '0;
                    if (result_idx == 4'hF) sending_results <= 1'b0;
                end
            end
        end
    end
endmodule
