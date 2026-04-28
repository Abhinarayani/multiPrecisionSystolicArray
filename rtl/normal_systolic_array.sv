// normal_systolic_array.sv
// Conventional 4x4 output-stationary systolic array baseline.

`include "bitsys_pkg.sv"

module normal_systolic_array
    import bitsys_pkg::*;
#(
    parameter int N = SA_SIZE
)(
    input  logic            clk,
    input  logic            rst_n,
    input  logic            start,
    input  logic [1:0]      prec,
    input  logic            is_signed,
    input  logic            bnn_mode,
    input  logic [7:0]      a_in [0:N-1],
    input  logic [7:0]      b_in [0:N-1],
    output logic            output_valid,
    output logic signed [31:0] c_out [0:N-1][0:N-1]
);
    localparam int DONE_CYCLE = 3*N - 1;
    localparam int CNT_W      = $clog2(4*N + 4);

    logic [CNT_W-1:0] cycle_cnt;
    logic [7:0] a_skew [0:N-1][0:N];
    logic [7:0] b_skew [0:N-1][0:N];
    logic [7:0] a_h [0:N-1][0:N];
    logic [7:0] b_v [0:N][0:N-1];
    logic [3*N-3:0] clear_sr;
    logic data_valid;
    logic signed [31:0] pe_result [0:N-1][0:N-1];

    logic _unused;
    assign _unused = ^{prec, is_signed, bnn_mode};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++)
                for (int d = 0; d <= N; d++) begin
                    a_skew[i][d] <= '0;
                    b_skew[i][d] <= '0;
                end
        end else if (start || data_valid) begin
            for (int i = 0; i < N; i++) begin
                a_skew[i][0] <= a_in[i];
                b_skew[i][0] <= b_in[i];
                for (int d = 1; d <= N; d++) begin
                    a_skew[i][d] <= a_skew[i][d-1];
                    b_skew[i][d] <= b_skew[i][d-1];
                end
            end
        end
    end

    generate
        for (genvar i = 0; i < N; i++) begin : init_a_h
            assign a_h[i][0] = a_skew[i][i];
        end
        for (genvar j = 0; j < N; j++) begin : init_b_v
            assign b_v[0][j] = b_skew[j][j];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) clear_sr <= '0;
        else if (start || data_valid) clear_sr <= {clear_sr[3*N-4:0], start};
    end

    assign data_valid = |clear_sr;

    generate
        for (genvar i = 0; i < N; i++) begin : row_g
            for (genvar j = 0; j < N; j++) begin : col_g
                normal_mac u_mac (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .clear (clear_sr[i+j]),
                    .en    (data_valid),
                    .a_in  (signed'(a_h[i][j])),
                    .b_in  (signed'(b_v[i][j])),
                    .a_out (a_h[i][j+1]),
                    .b_out (b_v[i+1][j]),
                    .result(pe_result[i][j])
                );
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt <= '0;
        end else if (start) begin
            cycle_cnt <= 1;
        end else if (cycle_cnt != '0) begin
            cycle_cnt <= cycle_cnt + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid <= 1'b0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    c_out[i][j] <= 32'sd0;
        end else if (start) begin
            output_valid <= 1'b0;
        end else if (cycle_cnt == CNT_W'(DONE_CYCLE)) begin
            output_valid <= 1'b1;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    c_out[i][j] <= pe_result[i][j];
        end else begin
            output_valid <= 1'b0;
        end
    end
endmodule
