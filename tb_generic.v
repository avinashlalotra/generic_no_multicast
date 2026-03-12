`timescale 1ns/1ps

module tb_generic;

reg clk = 0;
reg rst = 1;
reg start = 0;

wire valid;
wire [31:0] data;
wire [2:0] pathbits;

packet_generator_generic #(
    .NUM_MS(8)
) dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .M(8'd2),
    .N(8'd2),
    .K(8'd2),
    .B_base_ptr(32'h2000),
    .valid(valid),
    .data(data),
    .pathbits(pathbits)
);

always #5 clk = ~clk;

initial begin
    #20 rst = 0;
    #10 start = 1;
    #10 start = 0;

    #2000 $finish;
end

always @(posedge clk) begin
    if(valid)
        $display("time=%0t data=%h path=%b",$time,data,pathbits);
end

endmodule