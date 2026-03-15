module path_bit_gen_top #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4,
    parameter BV_ADDR_W = 4,
    parameter A_INIT_FILE = "",
    parameter B_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire [1:0] cmd,
    input wire cmd_valid,

    // Config packet stream
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,

    // Data packet stream
    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,

    // BV memory read port (external)
    input  wire [BV_ADDR_W-1:0] bv_addr,
    input  wire bv_ren,
    output wire [NUM_MS-1:0] bv_rdata,

    output wire ack
);

    // Internal memory interface wires
    wire [A_ADDR_W-1:0] a_addr;
    wire a_ren;
    wire [DATA_W-1:0] a_data;

    wire [B_ADDR_W-1:0] b_addr;
    wire b_ren;
    wire [DATA_W-1:0] b_data;

    // BV write port from scheduler
    wire [BV_ADDR_W-1:0] bv_waddr;
    wire bv_wen;
    wire [NUM_MS-1:0] bv_wdata;

    // Instantiate matrix memories
    // Scheduler handles addressing directly (including +2 offset for elements)
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

    // BV memory: written by scheduler, read externally
    simple_mem_dp #(
        .DATA_W(NUM_MS),
        .ADDR_W(BV_ADDR_W)
    ) bv_mem (
        .clk(clk),
        .wen(bv_wen),
        .waddr(bv_waddr),
        .wdata(bv_wdata),
        .ren(bv_ren),
        .raddr(bv_addr),
        .rdata(bv_rdata)
    );

    // Instantiate scheduler wrapper
    scheduler_wrapper #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W)
    ) wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(cmd),
        .cmd_valid(cmd_valid),

        .a_addr(a_addr),
        .a_ren(a_ren),
        .a_data(a_data),

        .b_addr(b_addr),
        .b_ren(b_ren),
        .b_data(b_data),

        .bv_waddr(bv_waddr),
        .bv_wen(bv_wen),
        .bv_wdata(bv_wdata),

        .config_en(config_en),
        .config_rdy(config_rdy),
        .config_data(config_data),

        .data_en(data_en),
        .data_rdy(data_rdy),
        .data_data(data_data),

        .ack(ack)
    );

endmodule
