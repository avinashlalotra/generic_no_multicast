module ms_config_top #(
    parameter M = 2,
    parameter K = 1,
    parameter N = 2,
    parameter NUM_MS = 4,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 6,
    parameter B_ADDR_W = 6,
    parameter A_INIT_FILE = "",
    parameter B_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    
    // MS Config stream (MN)
    output wire ms_config_en,
    input  wire ms_config_rdy,
    output wire [(20*NUM_MS)-1:0] ms_config_data,
    
    // Packet distribution network (DN) mapping
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,
    
    // Packet data stream
    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,
    
    output wire done
);

    wire [A_ADDR_W-1:0] a_addr;
    wire a_ren;
    wire [DATA_W-1:0] a_data;

    wire [B_ADDR_W-1:0] b_addr;
    wire b_ren;
    wire [DATA_W-1:0] b_data;

    // Instantiate memories
    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(A_ADDR_W),
        .INIT_FILE(A_INIT_FILE)
    ) mem_A (
        .clk(clk),
        .ren(a_ren),
        .addr(a_addr),
        .rdata(a_data)
    );

    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(B_ADDR_W),
        .INIT_FILE(B_INIT_FILE)
    ) mem_B (
        .clk(clk),
        .ren(b_ren),
        .addr(b_addr),
        .rdata(b_data)
    );

    // Instantiate scheduler wrapper
    scheduler_wrapper #(
        .M(M),
        .K(K),
        .N(N),
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W)
    ) wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        
        .a_addr(a_addr),
        .a_ren(a_ren),
        .a_data(a_data),
        
        .b_addr(b_addr),
        .b_ren(b_ren),
        .b_data(b_data),
        
        .ms_config_en(ms_config_en),
        .ms_config_rdy(ms_config_rdy),
        .ms_config_data(ms_config_data),
        
        .config_en(config_en),
        .config_rdy(config_rdy),
        .config_data(config_data),
        
        .data_en(data_en),
        .data_rdy(data_rdy),
        .data_data(data_data),
        
        .done(done)
    );

endmodule
