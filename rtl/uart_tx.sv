// uart_tx.sv
// UART Transmitter
//
// Transmits serial data at configurable baud rate.
// Data format: 1 start bit, 8 data bits, 1 stop bit
// Accepts data_in and send signal, raises busy during transmission.

module uart_tx (
    input  logic clk,
    input  logic rst_n,
    input  logic [7:0] data_in,
    input  logic send,         // pulse to send a byte
    input  logic [15:0] baud_count,  // clock cycles per bit
    output logic tx,           // serial output line
    output logic busy
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;
    logic [3:0] bit_count;
    logic [15:0] sample_count;
    logic [7:0] shift_reg;

    // State machine for transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= '0;
            sample_count <= '0;
            shift_reg <= '0;
            tx <= 1'b1;  // Idle line is high
        end else begin
            state <= next_state;
            sample_count <= sample_count + 1;

            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    sample_count <= '0;
                    if (send) begin
                        shift_reg <= data_in;
                        bit_count <= '0;
                    end
                end

                START: begin
                    tx <= 1'b0;  // Send start bit
                    if (sample_count == baud_count - 1) begin
                        sample_count <= '0;
                        bit_count <= '0;
                    end
                end

                DATA: begin
                    tx <= shift_reg[0];  // Send LSB first
                    if (sample_count == baud_count - 1) begin
                        sample_count <= '0;
                        shift_reg <= {1'b0, shift_reg[7:1]};  // Shift right
                        bit_count <= bit_count + 1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // Send stop bit
                    if (sample_count == baud_count - 1) begin
                        sample_count <= '0;
                    end
                end

                default: begin
                    tx <= 1'b1;
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (send)
                    next_state = START;
            end

            START: begin
                if (sample_count == baud_count - 1)
                    next_state = DATA;
            end

            DATA: begin
                if ((bit_count == 7) && (sample_count == baud_count - 1))
                    next_state = STOP;
            end

            STOP: begin
                if (sample_count == baud_count - 1)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    assign busy = (state != IDLE);

endmodule
