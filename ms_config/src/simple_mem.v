module simple_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4,
    parameter INIT_FILE = "" // File to initialize memory from
)(
    input wire clk,
    input wire ren,
    input wire [ADDR_W-1:0] addr,
    output reg [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end
endmodule
