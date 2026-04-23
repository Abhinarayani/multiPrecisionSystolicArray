// bitsys_uart_top.sv
// Top-level: UART ↔ bitsys_systolic_array controller
//
// ─── PC → FPGA packet (33 bytes total) ────────────────────────────────────────
//   Byte  0      : config  = { bnn_mode[7], is_signed[6], prec[5:4], 4'b0 }
//   Bytes 1..16  : Matrix A, row-major  A[0][0] A[0][1] … A[3][3]  (int8)
//   Bytes 17..32 : Matrix B, row-major  B[0][0] B[0][1] … B[3][3]  (int8)
//
// ─── FPGA → PC packet (64 bytes total) ────────────────────────────────────────
//   For each element C[i][j] (row-major, i=0..3, j=0..3):
//     4 bytes, big-endian (MSB first): c_out[i][j][31:24] … c_out[i][j][7:0]
//
// ─── Feed sequence (mirrors run_matmul task in tb_bitsys_systolic_array.sv) ───
//   Cycle 0 : start=1, a_in[i]=A[i][0], b_in[j]=B[0][j]   (k=0)
//   Cycle 1 : start=0, a_in[i]=A[i][1], b_in[j]=B[1][j]   (k=1)
//   Cycle 2 : start=0, a_in[i]=A[i][2], b_in[j]=B[2][j]   (k=2)
//   Cycle 3 : start=0, a_in[i]=A[i][3], b_in[j]=B[3][j]   (k=3)
//   Cycle 4 : start=0, a_in=0, b_in=0                      (drain)
//   Wait output_valid → capture c_out → transmit 64 bytes
//
// ─── Assumptions ──────────────────────────────────────────────────────────────
//   CLK_FREQ : system clock frequency (default 50 MHz)
//   BAUD     : 115200
//   N        : systolic array size (default 4, must match bitsys_pkg::SA_SIZE)

`timescale 1ns/1ps

module bitsys_uart_top
    import bitsys_pkg::*;
#(
    parameter int CLK_FREQ = 50_000_000,
    parameter int BAUD     = 115_200,
    parameter int N        = SA_SIZE          // must equal 4 for this packet layout
)(
    input  logic clk,
    input  logic rst_n,
    input  logic uart_rx_pin,
    output logic uart_tx_pin
    output logic led_rx,       // ← add
    output logic led_tx        // ← add
);

    // -------------------------------------------------------------------------
    // Baud divider (static, fits in 16 bits for standard FPGA clocks ≤ 7.5 GHz)
    // -------------------------------------------------------------------------
    localparam logic [15:0] BAUD_DIV = CLK_FREQ / BAUD;

    // -------------------------------------------------------------------------
    // UART RX wires
    // -------------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_valid;   // 1-cycle pulse when byte is ready
    logic       rx_busy;

    uart_rx u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (uart_rx_pin),
        .baud_count (BAUD_DIV),
        .data       (rx_data),
        .data_valid (rx_valid),
        .busy       (rx_busy)
    );

    // -------------------------------------------------------------------------
    // UART TX wires
    // -------------------------------------------------------------------------
    logic [7:0] tx_data;
    logic       tx_send;
    logic       tx_busy;

    uart_tx u_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_in    (tx_data),
        .send       (tx_send),
        .baud_count (BAUD_DIV),
        .tx         (uart_tx_pin),
        .busy       (tx_busy)
    );

    // -------------------------------------------------------------------------
    // DUT wires
    // -------------------------------------------------------------------------
    logic            dut_start;
    logic [1:0]      dut_prec;
    logic            dut_is_signed;
    logic            dut_bnn_mode;
    logic [7:0]      dut_a_in [0:N-1];
    logic [7:0]      dut_b_in [0:N-1];
    logic            dut_output_valid;
    logic signed [31:0] dut_c_out [0:N-1][0:N-1];

    bitsys_systolic_array #(.N(N)) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (dut_start),
        .prec         (dut_prec),
        .is_signed    (dut_is_signed),
        .bnn_mode     (dut_bnn_mode),
        .a_in         (dut_a_in),
        .b_in         (dut_b_in),
        .output_valid (dut_output_valid),
        .c_out        (dut_c_out)
    );

    // -------------------------------------------------------------------------
    // Receive buffers
    // 1 config byte + 16 A bytes + 16 B bytes = 33 bytes
    // -------------------------------------------------------------------------
    localparam int RX_TOTAL = 33;

    logic [7:0]  cfg_byte;
    logic [7:0]  mat_a [0:N-1][0:N-1];   // mat_a[row][col]
    logic [7:0]  mat_b [0:N-1][0:N-1];

    // -------------------------------------------------------------------------
    // Transmit FIFO  (64 bytes: 16 elements × 4 bytes each)
    // -------------------------------------------------------------------------
    localparam int TX_TOTAL = N * N * 4;  // = 64

    logic [7:0]  tx_fifo [0:TX_TOTAL-1];
    logic [6:0]  tx_ptr;   // 0..63
    logic        tx_active;
    logic        tx_send_r;     // registered send pulse (1-cycle)

    // -------------------------------------------------------------------------
    // Feed-sequence registers (mirror of TB's run_matmul variables)
    // -------------------------------------------------------------------------
    logic [7:0]  feed_a_in [0:N-1];   // registered inputs to DUT
    logic [7:0]  feed_b_in [0:N-1];
    logic        feed_start;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE,       // waiting for first byte of packet
        S_RX,         // receiving remaining bytes
        S_FEED,       // feeding matrix data to DUT (k=0..N-1 then drain)
        S_WAIT_VALID, // waiting for output_valid
        S_TX_LOAD,    // load TX FIFO from c_out
        S_TX_SEND,    // transmit bytes one by one
        S_TX_WAIT     // wait for TX not busy between bytes
    } state_t;

    state_t state;

    localparam int        FEED_MAX  = N;          // drain fires when feed_k == N
    localparam logic [2:0] FEED_MAX3 = 3'(FEED_MAX); // 3-bit version for comparisons

    logic [5:0] rx_cnt;   // bytes received so far (0 = first = config)
    logic [2:0] feed_k;   // feed cycle index 0..N (N = drain cycle)

    // -------------------------------------------------------------------------
    // Combinational: decode stored config
    // -------------------------------------------------------------------------
    assign dut_bnn_mode  = cfg_byte[7];
    assign dut_is_signed = cfg_byte[6];
    assign dut_prec      = cfg_byte[5:4];

    // -------------------------------------------------------------------------
    // Combinational: connect registered feed signals to DUT
    // -------------------------------------------------------------------------
    always_comb begin
        dut_start = feed_start;
        for (int i = 0; i < N; i++) begin
            dut_a_in[i] = feed_a_in[i];
            dut_b_in[i] = feed_b_in[i];
        end
    end

    // -------------------------------------------------------------------------
    // TX send pulse: assert for exactly 1 cycle when TX is free and active
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_send_r <= 1'b0;
        else
            tx_send_r <= (state == S_TX_SEND) && !tx_busy;
    end

    assign tx_send = tx_send_r;
    assign tx_data = tx_fifo[tx_ptr];

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            rx_cnt     <= '0;
            feed_k     <= '0;
            feed_start <= 1'b0;
            tx_active  <= 1'b0;
            tx_ptr     <= '0;
            cfg_byte   <= '0;
            for (int i = 0; i < N; i++) begin
                feed_a_in[i] <= 8'b0;
                feed_b_in[i] <= 8'b0;
            end
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++) begin
                    mat_a[i][j] <= 8'b0;
                    mat_b[i][j] <= 8'b0;
                end
        end else begin

            // Default: clear feed_start each cycle (TB: start is only high 1 cycle)
            feed_start <= 1'b0;

            case (state)

                // ─────────────────────────────────────────────────────────────
                // S_IDLE: wait for the config byte (first byte of a new packet)
                // ─────────────────────────────────────────────────────────────
                S_IDLE: begin
                    rx_cnt   <= '0;
                    feed_k   <= '0;
                    tx_ptr   <= '0;
                    tx_active <= 1'b0;
                    // Zero the DUT feed lines
                    for (int i = 0; i < N; i++) begin
                        feed_a_in[i] <= 8'b0;
                        feed_b_in[i] <= 8'b0;
                    end
                    if (rx_valid) begin
                        cfg_byte <= rx_data;   // byte 0 = config
                        rx_cnt   <= 6'd1;
                        state    <= S_RX;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_RX: accumulate 32 matrix bytes (bytes 1..32)
                //   Byte index b:
                //     1..16  → A[(b-1)/N][(b-1)%N]
                //     17..32 → B[(b-17)/N][(b-17)%N]
                // ─────────────────────────────────────────────────────────────
                S_RX: begin
                    if (rx_valid) begin
                        if (rx_cnt <= 6'd16) begin
                            // Matrix A bytes 1..16  (rx_cnt 1..16)
                            mat_a[(rx_cnt - 1) / N][(rx_cnt - 1) % N] <= rx_data;
                        end else begin
                            // Matrix B bytes 17..32 (rx_cnt 17..32)
                            mat_b[(rx_cnt - 17) / N][(rx_cnt - 17) % N] <= rx_data;
                        end

                        if (rx_cnt == 6'd32) begin
                            // All 32 data bytes received; start feeding DUT
                            rx_cnt <= '0;
                            feed_k <= '0;
                            state  <= S_FEED;
                        end else begin
                            rx_cnt <= rx_cnt + 1;
                        end
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_FEED: one state cycle = one DUT clock cycle
                //   Mirrors TB run_matmul feed loop exactly:
                //     feed_k == 0        : start=1, drive A[:,0] and B[0,:]
                //     feed_k == 1..N-1   : start=0, drive A[:,k] and B[k,:]
                //     feed_k == N (drain): start=0, drive zeros
                // ─────────────────────────────────────────────────────────────
                S_FEED: begin
                    if (feed_k <= FEED_MAX3) begin
                        if (feed_k == 3'd0) begin
                            // k=0: assert start, feed column 0 of A and row 0 of B
                            feed_start <= 1'b1;
                            for (int i = 0; i < N; i++)
                                feed_a_in[i] <= mat_a[i][0];
                            for (int j = 0; j < N; j++)
                                feed_b_in[j] <= mat_b[0][j];
                        end else if (feed_k < FEED_MAX3) begin
                            // k=1..N-1: feed column k of A and row k of B
                            feed_start <= 1'b0;
                            for (int i = 0; i < N; i++)
                                feed_a_in[i] <= mat_a[i][feed_k];
                            for (int j = 0; j < N; j++)
                                feed_b_in[j] <= mat_b[feed_k][j];
                        end else begin
                            // k==N: drain cycle — zero inputs
                            feed_start <= 1'b0;
                            for (int i = 0; i < N; i++) begin
                                feed_a_in[i] <= 8'b0;
                                feed_b_in[i] <= 8'b0;
                            end
                        end

                        feed_k <= feed_k + 1;

                        if (feed_k == FEED_MAX3) begin
                            // Drain cycle just launched; now wait for output_valid
                            state <= S_WAIT_VALID;
                        end
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_WAIT_VALID: hold zeros on DUT inputs; wait for output_valid
                // ─────────────────────────────────────────────────────────────
                S_WAIT_VALID: begin
                    if (dut_output_valid) begin
                        state <= S_TX_LOAD;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_TX_LOAD: flatten c_out[i][j] (32-bit signed, big-endian)
                //   into tx_fifo[0..63] in row-major order
                // ─────────────────────────────────────────────────────────────
                S_TX_LOAD: begin
                    for (int i = 0; i < N; i++) begin
                        for (int j = 0; j < N; j++) begin
                            // Each element occupies 4 consecutive bytes
                            // Element index e = i*N + j → bytes at 4*e..4*e+3
                            tx_fifo[4*(i*N+j) + 0] <= dut_c_out[i][j][31:24];
                            tx_fifo[4*(i*N+j) + 1] <= dut_c_out[i][j][23:16];
                            tx_fifo[4*(i*N+j) + 2] <= dut_c_out[i][j][15: 8];
                            tx_fifo[4*(i*N+j) + 3] <= dut_c_out[i][j][ 7: 0];
                        end
                    end
                    tx_ptr    <= '0;
                    tx_active <= 1'b1;
                    state     <= S_TX_SEND;
                end

                // ─────────────────────────────────────────────────────────────
                // S_TX_SEND: assert send for 1 cycle when TX is free
                //   (tx_send_r is the registered pulse driven outside FSM)
                // ─────────────────────────────────────────────────────────────
                S_TX_SEND: begin
                    if (!tx_busy) begin
                        // tx_send_r will pulse next cycle (see registered logic above)
                        state <= S_TX_WAIT;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // S_TX_WAIT: wait for TX to go busy (byte accepted), then
                //   advance pointer and either send next byte or finish
                // ─────────────────────────────────────────────────────────────
                S_TX_WAIT: begin
                    if (tx_busy) begin
                        // TX has accepted the byte and gone busy
                        if (tx_ptr == 7'(TX_TOTAL) - 1) begin
                            // All 64 bytes sent; return to IDLE for next packet
                            tx_active <= 1'b0;
                            state     <= S_IDLE;
                        end else begin
                            tx_ptr <= tx_ptr + 1;
                            state  <= S_TX_SEND;
                        end
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    

endmodule
