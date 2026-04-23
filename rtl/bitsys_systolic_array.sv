// bitsys_systolic_array.sv
// BitSys Systolic Array for Matrix Multiplication  C = A × B
//
// Architecture: output-stationary N×N systolic array.
// Each PE is a bitsys_mac that accumulates: C[i][j] += A[i][k] × B[k][j]
//
// --- Data flow ---
//   A rows flow left→right; B columns flow top→bottom.
//   Row i is delayed by i registers before the leftmost PE column.
//   Col j is delayed by j registers before the topmost PE row.
//   This skewing ensures A[i][k] and B[k][j] meet at PE(i,j) simultaneously.
//
// --- Timing (cycle-accurate, N=4 example) ---
//   Cycle 0 : start=1, feed A[i][0] into a_in[i], B[0][j] into b_in[j]
//   Cycle 1 : feed A[i][1], B[1][j]
//   ...
//   Cycle N-1: feed A[i][N-1], B[N-1][j]
//   Cycle N+ : zero inputs (pipeline drains naturally)
//
//   PE(i,j) clear fires at posedge i+j+1 (when first product arrives).
//   PE(i,j) last product accumulates at posedge N + i + j.
//   PE(N-1,N-1) finishes at posedge 3N-2.
//   output_valid flag rises one cycle later at posedge 3N-1 (DONE_CYCLE = 3N-1),
//   allowing pe_result to stabilise before the output capture register samples it.
//
// --- Clock Gating ---
// Uses integrated clock gating (ICG) cells to reduce dynamic power:
//   - Skew registers (a_skew, b_skew) gated by data_valid
//   - Clear shift register gated by (start | data_valid)
//   - Cycle counter gated by (start | (cycle_cnt != 0 && cycle_cnt <= DONE_CYCLE))
//   - Output capture uses FF clock-enable (not ICG) to avoid latch-delay race on clk_out
//
// --- Ports ---
//   a_in[i]     : element of A row i, column-streamed each cycle
//   b_in[j]     : element of B column j, row-streamed each cycle
//   output_valid: high for 1 cycle when c_out holds the final result
//   c_out[i][j] : latched output matrix (signed 32-bit accumulators)



module bitsys_systolic_array
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
    output var logic signed [31:0] c_out [0:N-1][0:N-1]
);

    // -----------------------------------------------------------------------
    // Clock gating signals and cells
    // -----------------------------------------------------------------------
    logic clk_skew;      // Gated clock for skew registers
    logic clk_clear;     // Gated clock for clear shift register
    logic clk_cnt;       // Gated clock for cycle counter
    // NOTE: clk_out removed — output capture now uses FF clock-enable (out_en)
    //       to avoid the 1-cycle latch delay that caused RTL-BUG-2/3.
    
    logic skew_en;       // Skew clock gate enable
    logic clear_en;      // Clear SR clock gate enable
    logic cnt_en;        // Counter clock gate enable
    logic out_en;        // Output FF clock-enable (NOT a gated clock)
    
    // -----------------------------------------------------------------------
    // Output valid and result capture timing parameters
    // DONE_CYCLE = 3*N - 1.
    // Last product accumulates at PE(N-1,N-1) on posedge 3N-2.
    // pe_result is not yet visible to the always_ff at that same posedge,
    // so we wait one more cycle: at posedge 3N-1, cycle_cnt == 3N-1,
    // pe_result holds the final values, and output_valid/c_out are latched.
    // -----------------------------------------------------------------------
    localparam int DONE_CYCLE = 3*N - 1;
    localparam int CNT_W      = $clog2(4*N + 4);
    logic [CNT_W-1:0] cycle_cnt;
    
    // -----------------------------------------------------------------------
    // Input skew registers
    // a_skew[i][d]: d-stage pipeline for row i's input
    // b_skew[j][d]: d-stage pipeline for col j's input
    // The leftmost PE column receives a_skew[i][i] (i cycles delayed).
    // The topmost PE row  receives b_skew[j][j] (j cycles delayed).
    // -----------------------------------------------------------------------
    logic [7:0] a_skew [0:N-1][0:N];   // [row][delay 0..N] (index N unused pad)
    logic [7:0] b_skew [0:N-1][0:N];

    always_ff @(posedge clk_skew or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++)
                for (int d = 0; d <= N; d++) begin
                    a_skew[i][d] <= 8'b0;
                    b_skew[i][d] <= 8'b0;
                end
        end else begin
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

    // -----------------------------------------------------------------------
    // Horizontal (A) and vertical (B) inter-PE wires
    // a_h[row][col=0] fed from a_skew[row][row]  (row-delay)
    // b_v[row=0][col]  fed from b_skew[col][col]  (col-delay)
    // -----------------------------------------------------------------------
    logic [7:0] a_h [0:N-1][0:N];   // col index N = sink (unused)
    logic [7:0] b_v [0:N][0:N-1];   // row index N = sink

    // always_comb begin
    //     for (int i = 0; i < N; i++)
    //         a_h[i][0] = a_skew[i][i];
    //     for (int j = 0; j < N; j++)
    //         b_v[0][j] = b_skew[j][j];
    // end

// --- REPLACE WITH THIS ---
    generate
        for (genvar i = 0; i < N; i++) begin : init_a_h
            assign a_h[i][0] = a_skew[i][i];
        end
        for (genvar j = 0; j < N; j++) begin : init_b_v
            assign b_v[0][j] = b_skew[j][j];
        end
    endgenerate


    // -----------------------------------------------------------------------
    // Clear shift register
    // clear_sr[n] = 1 is readable as FF output n+1 posedges after start.
    // PE(i,j) uses clear_sr[i+j]: fires when first product arrives.
    // -----------------------------------------------------------------------
    // Width must cover last accumulation at posedge (i+j+N) for PE(N-1,N-1):
    // posedge = 3N-2.  MAC samples data_valid from state after posedge 3N-3,
    // so bit must survive until position 3N-3 → need indices 0..3N-3 (3N-2 bits).
    logic [3*N-3:0] clear_sr;

    always_ff @(posedge clk_clear or negedge rst_n) begin
        if (!rst_n) clear_sr <= '0;
        else        clear_sr <= {clear_sr[3*N-4:0], start};
    end

    // -----------------------------------------------------------------------
    // Data-valid enable: any bit in clear_sr means the pipeline is active
    // -----------------------------------------------------------------------
    logic data_valid;
    assign data_valid = |clear_sr;

    // -----------------------------------------------------------------------
    // Clock gating cell instantiations
    // -----------------------------------------------------------------------
    
    // Skew registers gated by (start | data_valid) to capture input data immediately
    assign skew_en = start | data_valid;
    bitsys_clock_gate u_clk_gate_skew (
        .clk           (clk),
        .enable        (skew_en),
        .test_enable   (1'b0),
        .gated_clk     (clk_skew)
    );
    
    // Clear shift register gated by (start | data_valid)
    assign clear_en = start | data_valid;
    bitsys_clock_gate u_clk_gate_clear (
        .clk           (clk),
        .enable        (clear_en),
        .test_enable   (1'b0),
        .gated_clk     (clk_clear)
    );
    
    // Cycle counter gated by (start | (0 < cycle_cnt < DONE_CYCLE))
    // FIX RTL-BUG-1: upper bound is strictly less-than so cnt_en falls to 0
    // the cycle cycle_cnt reaches DONE_CYCLE, gating clk_cnt off and freezing
    // the counter.  The counter itself also has an explicit hold in the always_ff.
    assign cnt_en = start | (cycle_cnt != '0 && cycle_cnt < CNT_W'(DONE_CYCLE));
    bitsys_clock_gate u_clk_gate_cnt (
        .clk           (clk),
        .enable        (cnt_en),
        .test_enable   (1'b0),
        .gated_clk     (clk_cnt)
    );
    
    // FIX RTL-BUG-2/3: Output capture uses FF clock-enable (done_pulse), NOT a gated clock.
    // Removing the ICG latch on clk_out eliminates the 1-cycle delay that caused
    // the capture always_ff to miss cycle_cnt==DONE_CYCLE, and ensures the async
    // reset properly initialises c_out (no more X from uninitialised latch_out).
    //
    // done_pulse is a registered one-shot that fires for exactly 1 cycle when
    // cycle_cnt first reaches DONE_CYCLE.  Using a combinational out_en that stays
    // high while cycle_cnt is frozen at DONE_CYCLE would cause output_valid to be
    // re-asserted every cycle, so the one-shot is essential.
    logic done_pulse;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)     done_pulse <= 1'b0;
        else if (start) done_pulse <= 1'b0;
        else            done_pulse <= (cycle_cnt == CNT_W'(DONE_CYCLE - 1));
        // Fires for 1 cycle when counter transitions from DONE_CYCLE-1 to DONE_CYCLE
    end
    assign out_en = start | done_pulse;

    // -----------------------------------------------------------------------
    // PE grid (generate)
    // -----------------------------------------------------------------------
    logic signed [31:0] pe_result [0:N-1][0:N-1];

    generate
        for (genvar i = 0; i < N; i++) begin : row_g
            for (genvar j = 0; j < N; j++) begin : col_g
                bitsys_mac u_mac (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .clear    (clear_sr[i+j]),   // fires when first product arrives
                    .en       (data_valid),
                    .a_in     (a_h[i][j]),
                    .b_in     (b_v[i][j]),
                    .prec     (prec),
                    .is_signed(is_signed),
                    .bnn_mode (bnn_mode),
                    .a_out    (a_h[i][j+1]),
                    .b_out    (b_v[i+1][j]),
                    .result   (pe_result[i][j])
                );
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Cycle counter — uses gated clock (clk_cnt).
    // FIX RTL-BUG-1: counter now freezes once it reaches DONE_CYCLE.
    // The cnt_en gate already prevents clk_cnt from toggling beyond DONE_CYCLE,
    // but the explicit bound here is belt-and-braces correct-by-construction.
    // -----------------------------------------------------------------------
    always_ff @(posedge clk_cnt or negedge rst_n) begin
        if (!rst_n)     cycle_cnt <= '0;
        else if (start) cycle_cnt <= 1;
        else if (cycle_cnt < CNT_W'(DONE_CYCLE)) cycle_cnt <= cycle_cnt + 1;
        // else: cycle_cnt == DONE_CYCLE — hold; cnt_en will gate clk_cnt off next cycle
    end

    // -----------------------------------------------------------------------
    // Output capture — uses ungated clk.
    //
    // FIX RTL-BUG-2: Previously used always_ff @(posedge clk_out) where
    //   clk_out was generated by a latch-based ICG.  The latch captured
    //   out_en on negedge, so clk_out only rose one full cycle after
    //   cycle_cnt first equalled DONE_CYCLE — by which point cycle_cnt had
    //   already incremented past DONE_CYCLE, so the capture branch was never
    //   taken and c_out stayed X.
    //
    // FIX RTL-BUG-3: Using ungated clk means the async reset (negedge rst_n)
    //   fires against a known-stable clock, so c_out initialises cleanly to
    //   32'sd0 instead of X.
    //
    // output_valid is driven every cycle (not guarded by any enable) so that
    // the else-branch clears it each cycle — guaranteeing a 1-cycle pulse.
    // c_out is written only when done_pulse fires (1 cycle only per operation).
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid <= 1'b0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    c_out[i][j] <= 32'sd0;
        end else if (start) begin
            output_valid <= 1'b0;
        end else if (done_pulse) begin
            output_valid <= 1'b1;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    c_out[i][j] <= pe_result[i][j];
        end else begin
            output_valid <= 1'b0;
        end
    end

endmodule
