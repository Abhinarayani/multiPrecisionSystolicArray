// tb_bitsys_power.sv
// Power analysis testbench for bitsys_systolic_array
// Derived from tb_bitsys_systolic_array.sv — same DUT, same task skeleton.
//
// Changes for maximum dynamic power:
//   1. Inputs alternate between bitwise-complement patterns every transaction
//      so every FF and multiplier input toggles on every feed cycle.
//   2. 10 000 back-to-back transactions with no idle gaps.
//   3. Fix 1: $dumpoff/$dumpon in the single stimulus initial block —
//      VCD records the active window only, excluding reset and drain tail,
//      so Quartus averages toggle rates over the hot switching window.

`timescale 1ns/1ps

module tb_bitsys_power;
    import bitsys_pkg::*;

    localparam int N        = SA_SIZE;   // 4
    localparam int CLK      = 20;        // 20 ns → 50 MHz, matches device
    localparam int NUM_TXN  = 10_000;

    // -------------------------------------------------------------------------
    // DUT ports — identical to tb_bitsys_systolic_array
    // -------------------------------------------------------------------------
    logic            clk, rst_n, start;
    logic [1:0]      prec;
    logic            is_signed, bnn_mode;
    logic [7:0]      a_in [0:N-1];
    logic [7:0]      b_in [0:N-1];
    logic            output_valid;
    logic signed [31:0] c_out [0:N-1][0:N-1];

    bitsys_systolic_array #(.N(N)) dut (.*);

    initial clk = 0;
    always #(CLK/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Pattern ROM — 8 entries, every consecutive pair is a bitwise complement
    // so pat[k] XOR pat[k+1] == 8'hFF for all even k.
    // Rotating through these on every feed cycle ensures every bit of every
    // a_in/b_in lane toggles on every other transaction.
    // -------------------------------------------------------------------------
    localparam logic [7:0] PAT [0:7] = '{
        8'h55,   // 01010101
        8'hAA,   // 10101010  ← all 8 bits flip
        8'hFF,   // 11111111
        8'h00,   // 00000000  ← all 8 bits flip
        8'hF0,   // 11110000
        8'h0F,   // 00001111  ← all 8 bits flip
        8'h80,   // 10000000  (-128)
        8'h7F    // 01111111  ← all 8 bits flip
    };

    // -------------------------------------------------------------------------
    // Task: run one max-toggle matmul transaction
    //   Mirrors run_matmul from the original TB exactly —
    //   negedge-driven feed, wait output_valid, no result check needed.
    //   pat_base rotates by 1 each call so consecutive transactions are
    //   always complementary on every lane.
    // -------------------------------------------------------------------------
    task automatic run_power_txn(input logic [2:0] pat_base);

        // Feed cycles k = 0 .. N-1
        // Lane i gets PAT[(pat_base + i) % 8]       for a_in
        // Lane i gets PAT[(pat_base + i + 4) % 8]   for b_in (offset 4 = complement)
        @(negedge clk);
        start = 1'b1;
        for (int i = 0; i < N; i++) begin
            a_in[i] = PAT[(pat_base + i    ) % 8];
            b_in[i] = PAT[(pat_base + i + 4) % 8];
        end

        for (int k = 1; k < N; k++) begin
            @(negedge clk);
            start = 1'b0;
            for (int i = 0; i < N; i++) begin
                a_in[i] = PAT[(pat_base + i + k    ) % 8];
                b_in[i] = PAT[(pat_base + i + k + 4) % 8];
            end
        end

        // Drain cycle — zero inputs (mirrors original TB)
        @(negedge clk);
        start = 1'b0;
        for (int i = 0; i < N; i++) begin
            a_in[i] = 8'h00;
            b_in[i] = 8'h00;
        end

        // Wait for output_valid (mirrors original TB)
        @(posedge output_valid);
        @(negedge clk);

    endtask

    // -------------------------------------------------------------------------
    // Main stimulus — single initial block, VCD control embedded here
    // so there is no cross-block race on rst_n (Fix 1)
    // -------------------------------------------------------------------------
    logic [2:0] pat_idx;
    realtime    t_start, t_end;

    initial begin
        // ── Initialise — same as original TB ─────────────────────────────────
        rst_n     = 1'b0;
        start     = 1'b0;
        prec      = PREC_8B;
        is_signed = 1'b1;
        bnn_mode  = 1'b0;
        pat_idx   = 3'd0;
        for (int i = 0; i < N; i++) begin
            a_in[i] = 8'h00;
            b_in[i] = 8'h00;
        end

        // ── VCD: open file and scope to DUT only (not TB internals) ──────────
        // $dumpvars is called here so ModelSim registers hierarchy at time 0,
        // then we wait one clock edge before $dumpoff so the initial-value
        // snapshot ($dumpall checkpoint) is committed to the file.
        // Without that one-edge gap, ModelSim produces a 0-byte VCD.
        $dumpfile("tb_bitsys_power.vcd");
        $dumpvars(0, tb_bitsys_power.dut);   // DUT hierarchy only — no TB signals
        @(negedge clk);                       // one edge so initial snapshot commits
        $dumpoff;                             // pause — exclude reset from window

        // ── Reset ─────────────────────────────────────────────────────────────
        repeat(3) @(negedge clk);            // 4 negedges total including the one above
        rst_n = 1'b1;
        repeat(2) @(negedge clk);

        // ── Begin active VCD window ───────────────────────────────────────────
        $dumpon;
        t_start = $realtime;
        $display("[PWR] VCD recording started at %0t", t_start);
        $display("[PWR] Running %0d transactions at 50 MHz...", NUM_TXN);

        // ── 10 000 back-to-back transactions, no idle gaps ────────────────────
        // pat_idx increments by 1 each transaction so every consecutive pair
        // of transactions is bitwise-complementary on all input lanes —
        // maximum toggle density across the entire accumulator tree.
        repeat(NUM_TXN) begin
            run_power_txn(pat_idx);
            pat_idx = pat_idx + 3'd1;
        end

        // ── End active VCD window ─────────────────────────────────────────────
        t_end = $realtime;
        $dumpoff;

        $display("[PWR] VCD recording stopped  at %0t", t_end);
        $display("[PWR] Active window          : %0t", t_end - t_start);
        $display("[PWR] Transactions completed : %0d", NUM_TXN);
        $display("");
        $display("[PWR] Add to your .qsf:");
        $display("[PWR]   set_global_assignment -name POWER_USE_INPUT_FILE tb_bitsys_power.vcd");
        $display("[PWR]   set_global_assignment -name POWER_INPUT_FILE_TYPE VCD");
        $display("[PWR]   set_global_assignment -name POWER_VCD_SIMULATION_TIME_FROM \"%0t\"", t_start);
        $display("[PWR]   set_global_assignment -name POWER_VCD_SIMULATION_TIME_TO   \"%0t\"", t_end);
        $display("[PWR]   set_global_assignment -name POWER_VCD_SIGNAL_ACTIVITY_SCOPE \"|bitsys_uart_top|u_dut\"");

        #(CLK * 4);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog — NUM_TXN × (N feed + 1 drain + N wait) cycles × margin
    // -------------------------------------------------------------------------
    localparam int WATCHDOG_CYCLES = NUM_TXN * (N + 1 + N + 2) * 4;

    initial begin
        #(longint'(WATCHDOG_CYCLES) * CLK);  // cast prevents 32-bit overflow
        $display("TIMEOUT: exceeded %0d cycles", WATCHDOG_CYCLES);
        $finish;
    end

endmodule