// uart_rx.sv
// UART Receiver
//
// Receives serial data at configurable baud rate.
// Data format: 1 start bit, 8 data bits, 1 stop bit
// Generates valid signal when byte is received.

module uart_rx (
    input  logic clk,
    input  logic rst_n,
    input  logic rx,           // serial input line
    input  logic [15:0] baud_count,  // clock cycles per bit (clk_freq / baud_rate)
    output logic [7:0] data,
    output logic data_valid,
    output logic busy
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        STOP,
        VALID
    } state_t;

    state_t state, next_state;
    logic [3:0] bit_count;
    logic [15:0] sample_count;
    logic [7:0] shift_reg;
    logic rx_d1, rx_d2;  // Synchronization FF

    // Synchronize rx input
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d1 <= rx;
            rx_d2 <= rx_d1;
        end
    end

    // Main state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= '0;
            sample_count <= '0;
            shift_reg <= '0;
            data_valid <= 1'b0;
        end else begin
            state <= next_state;
            data_valid <= 1'b0;

            case (state)
                IDLE: begin
                    bit_count <= '0;
                    sample_count <= '0;
                end

                START: begin
                    sample_count <= sample_count + 1;
                    if (sample_count == (baud_count >> 1)) begin
                        // Sample in the middle of start bit
                        sample_count <= '0;
                        bit_count <= '0;
                    end
                end

                DATA: begin
                    sample_count <= sample_count + 1;
                    if (sample_count == baud_count - 1) begin
                        // Sample data bit
                        sample_count <= '0;
                        shift_reg <= {rx_d2, shift_reg[7:1]};
                        bit_count <= bit_count + 1;
                    end
                end

                STOP: begin
                    sample_count <= sample_count + 1;
                    if (sample_count == baud_count - 1) begin
                        // Sample stop bit
                        sample_count <= '0;
                        data_valid <= 1'b1;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (~rx_d2)  // Start bit detected
                    next_state = START;
            end

            START: begin
                if (sample_count == (baud_count >> 1))
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

    assign data = shift_reg;
    assign busy = (state != IDLE);

endmodule
