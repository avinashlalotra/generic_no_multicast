module scheduler_wrapper #(
    parameter M = 2,
    parameter K = 2,
    parameter N = 2,
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    
    // Memory interface A
    output wire [A_ADDR_W-1:0] a_addr,
    output wire a_ren,
    input  wire [DATA_W-1:0] a_data,
    
    // Memory interface B
    output wire [B_ADDR_W-1:0] b_addr,
    output wire b_ren,
    input  wire [DATA_W-1:0] b_data,
    
    // Config packet stream
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,
    
    // Data packet stream
    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,
    
    // MS config stream
    output wire ms_config_en,
    input  wire ms_config_rdy,
    output wire [(20*NUM_MS)-1:0] ms_config_data,
    
    output wire done
);

    wire out_ready = config_rdy & data_rdy;
    
    wire a_pkt_valid;
    wire [DATA_W-1:0] a_pkt_value;
    wire [NUM_MS-1:0] a_pkt_mask;
    
    wire b_pkt_valid;
    wire [DATA_W-1:0] b_pkt_value;
    wire [NUM_MS-1:0] b_pkt_mask;
    
    packet_scheduler #(
        .M(M), .K(K), .N(N), .NUM_MS(NUM_MS), .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W), .B_ADDR_W(B_ADDR_W)
    ) sched (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .out_ready(out_ready),
        
        .a_addr(a_addr),
        .a_ren(a_ren),
        .a_data(a_data),
        
        .b_addr(b_addr),
        .b_ren(b_ren),
        .b_data(b_data),
        
        .ms_config_en(ms_config_en),
        .ms_config_rdy(ms_config_rdy),
        .ms_config_data(ms_config_data),
        
        .a_pkt_valid(a_pkt_valid),
        .a_pkt_value(a_pkt_value),
        .a_pkt_mask(a_pkt_mask),
        
        .b_pkt_valid(b_pkt_valid),
        .b_pkt_value(b_pkt_value),
        .b_pkt_mask(b_pkt_mask),
        
        .done(done)
    );
    
    assign config_en = a_pkt_valid | b_pkt_valid;
    assign data_en   = a_pkt_valid | b_pkt_valid;
    
    assign config_data = a_pkt_valid ? a_pkt_mask : (b_pkt_valid ? b_pkt_mask : {NUM_MS{1'b0}});
    assign data_data   = a_pkt_valid ? a_pkt_value : (b_pkt_valid ? b_pkt_value : {DATA_W{1'b0}});

endmodule
