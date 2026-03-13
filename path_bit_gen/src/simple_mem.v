module simple_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4
)(
    input wire clk,
    input wire ren,
    input wire [ADDR_W-1:0] addr,
    output reg [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end
endmodule
