// Dual-port simple memory: 1 write port + 1 read port
module simple_mem_dp #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4
)(
    input wire clk,

    // Write port
    input wire wen,
    input wire [ADDR_W-1:0] waddr,
    input wire [DATA_W-1:0] wdata,

    // Read port
    input wire ren,
    input wire [ADDR_W-1:0] raddr,
    output reg [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[raddr];
        end
    end
endmodule
