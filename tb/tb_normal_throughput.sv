// tb_normal_throughput.sv
// Measure cycle-accurate throughput metrics for the conventional 8-bit systolic baseline.

`timescale 1ns/1ps

module tb_normal_throughput;
    import bitsys_pkg::*;

    localparam int N = SA_SIZE;
    localparam int CLK_PERIOD_NS = 10;
    localparam int HW_CLK_HZ = 50_000_000;
    localparam real HW_CLK_PERIOD_NS = 1.0e9 / HW_CLK_HZ;

    logic clk;
    logic rst_n;
    logic start;
    logic [1:0] prec;
    logic is_signed;
    logic bnn_mode;
    logic [7:0] a_in [0:N-1];
    logic [7:0] b_in [0:N-1];
    logic output_valid;
    logic signed [31:0] c_out [0:N-1][0:N-1];

    int cycle_ctr;

    normal_systolic_array #(.N(N)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .prec(prec),
        .is_signed(is_signed),
        .bnn_mode(bnn_mode),
        .a_in(a_in),
        .b_in(b_in),
        .output_valid(output_valid),
        .c_out(c_out)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_ctr <= 0;
        else        cycle_ctr <= cycle_ctr + 1;
    end

    task automatic zero_inputs();
        for (int i = 0; i < N; i++) begin
            a_in[i] = '0;
            b_in[i] = '0;
        end
    endtask

    task automatic apply_reset();
        @(negedge clk);
        rst_n = 1'b0;
        start = 1'b0;
        zero_inputs();
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
    endtask

    task automatic load_k(
        input int k,
        input logic [7:0] A [0:N-1][0:N-1],
        input logic [7:0] B [0:N-1][0:N-1]
    );
        for (int i = 0; i < N; i++) a_in[i] = A[i][k];
        for (int j = 0; j < N; j++) b_in[j] = B[k][j];
    endtask

    task automatic run_baseline();
        logic [7:0] A [0:N-1][0:N-1];
        logic [7:0] B [0:N-1][0:N-1];
        int start_cycle;
        int done_cycle;
        int sampled_cycle_count;
        int elapsed_cycles;
        real latency_ns;
        real matrix_per_sec;
        real scalar_macs_per_sec;
        real scalar_ops_per_sec;
        real macs_per_cycle;
        real ops_per_cycle;

        A = '{
            '{8'd1, 8'd2, 8'd3, 8'd0},
            '{8'd0, 8'd1, 8'd2, 8'd3},
            '{8'd3, 8'd0, 8'd1, 8'd2},
            '{8'd2, 8'd3, 8'd0, 8'd1}
        };

        B = '{
            '{8'd1, 8'd0, 8'd1, 8'd0},
            '{8'd0, 8'd1, 8'd0, 8'd1},
            '{8'd1, 8'd1, 8'd0, 8'd0},
            '{8'd0, 8'd0, 8'd1, 8'd1}
        };

        apply_reset();

        // Baseline is fixed 8-bit signed MAC behavior.
        prec = PREC_8B;
        is_signed = 1'b1;
        bnn_mode = 1'b0;

        @(negedge clk);
        start = 1'b1;
        load_k(0, A, B);

        @(posedge clk);
        start_cycle = cycle_ctr;

        for (int k = 1; k < N; k++) begin
            @(negedge clk);
            start = 1'b0;
            load_k(k, A, B);
        end

        @(negedge clk);
        start = 1'b0;
        zero_inputs();

        @(posedge output_valid);
        done_cycle = cycle_ctr;

        sampled_cycle_count = done_cycle - start_cycle + 1;
        elapsed_cycles = done_cycle - start_cycle;
        latency_ns = elapsed_cycles * HW_CLK_PERIOD_NS;
        matrix_per_sec = HW_CLK_HZ / real'(elapsed_cycles);
        scalar_macs_per_sec = matrix_per_sec * (N * N * N);
        scalar_ops_per_sec = scalar_macs_per_sec * 2.0;
        macs_per_cycle = real'(N * N * N) / real'(elapsed_cycles);
        ops_per_cycle = (real'(N * N * N) * 2.0) / real'(elapsed_cycles);

        $display("");
        $display("RTL throughput measurement for normal 8-bit systolic array");
        $display("  standardized kernel    : 4x4 x 4x4 matrix multiply");
        $display("  sampled cycle count   : %0d cycles", sampled_cycle_count);
        $display("  elapsed latency       : %0d cycles", elapsed_cycles);
        $display("  equivalent @50 MHz    : %0.1f ns", latency_ns);
        $display("  MACs / cycle          : %0.6f", macs_per_cycle);
        $display("  operations / cycle    : %0.6f", ops_per_cycle);
        $display("  matrix results / sec  : %0.6f M", matrix_per_sec / 1.0e6);
        $display("  scalar MACs / sec     : %0.6f G", scalar_macs_per_sec / 1.0e9);
        $display("  scalar ops / sec      : %0.6f G", scalar_ops_per_sec / 1.0e9);
        $display(
            "RESULT mode=normal-8-bit elapsed_cycles=%0d sampled_cycles=%0d macs_per_cycle=%0.6f ops_per_cycle=%0.6f matrix_per_sec=%0.6f scalar_gmac=%0.6f scalar_gops=%0.6f",
            elapsed_cycles,
            sampled_cycle_count,
            macs_per_cycle,
            ops_per_cycle,
            matrix_per_sec / 1.0e6,
            scalar_macs_per_sec / 1.0e9,
            scalar_ops_per_sec / 1.0e9
        );
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        prec = PREC_8B;
        is_signed = 1'b1;
        bnn_mode = 1'b0;
        zero_inputs();

        $display("=========================================================");
        $display(" Normal RTL Throughput Measurement (N=%0d)", N);
        $display("=========================================================");

        run_baseline();

        $display("");
        $display("Normal systolic array throughput measurement complete.");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
