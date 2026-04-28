// normal_mac.sv
// Conventional 8-bit signed MAC for a standard systolic array baseline.

module normal_mac (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               clear,
    input  logic               en,
    input  logic signed [7:0]  a_in,
    input  logic signed [7:0]  b_in,
    output logic signed [7:0]  a_out,
    output logic signed [7:0]  b_out,
    output logic signed [31:0] result
);
    logic signed [15:0] product;

    assign product = a_in * b_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 32'sd0;
        end else if (clear) begin
            result <= 32'(product);
        end else if (en) begin
            result <= result + 32'(product);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= '0;
            b_out <= '0;
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end
endmodule
