module tb_self_top;

localparam NUM_MS = 8;
localparam DATA_W = 16;
localparam A_ADDR_W = 4;
localparam B_ADDR_W = 4;
localparam BV_ADDR_W = 4;

// parameters
localparam A_INIT_FILE = "tb/mem_A_2x2.hex";
localparam B_INIT_FILE = "tb/mem_B_2x2.hex";


// Command encoding
    localparam CMD_IDLE     = 2'b00;
    localparam CMD_ALLOC_VN = 2'b01;
    localparam CMD_SEND_A   = 2'b10;
    localparam CMD_SEND_B   = 2'b11;

// DUT signals

reg clk;
reg rst_n;

reg [1:0] cmd;
reg cmd_valid;

wire config_en;
reg  config_rdy;
wire [NUM_MS-1:0] config_data;

wire data_en;
reg  data_rdy;
wire [DATA_W-1:0] data_data;

reg  [BV_ADDR_W-1:0] bv_addr;
reg  bv_ren;
wire [NUM_MS-1:0] bv_rdata;

wire ack;

// Instantiate DUT
path_bit_gen_top #(
    .A_INIT_FILE(A_INIT_FILE),
    .B_INIT_FILE(B_INIT_FILE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .cmd(cmd),
    .cmd_valid(cmd_valid),
    .config_en(config_en),
    .config_rdy(config_rdy),
    .config_data(config_data),
    .data_en(data_en),
    .data_rdy(data_rdy),
    .data_data(data_data),
    .bv_addr(bv_addr),
    .bv_ren(bv_ren),
    .bv_rdata(bv_rdata),
    .ack(ack)
);

// Print packets whenever they are valid and accepted
always @(posedge clk) begin
    if (config_en && data_en && config_rdy && data_rdy) begin
        $display("Time %0t: Packet -> Val=%0d  Mask=%08b", $time, data_data, config_data);
    end
end

// clk 
initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end


initial begin
    rst_n = 1'b0;
    config_rdy = 1'b1;
    data_rdy = 1'b1;
    bv_addr = 0;
    bv_ren = 1'b0;
    cmd = CMD_IDLE;
    cmd_valid = 1'b0;
    #20 rst_n = 1'b1;
    @(posedge clk);


    cmd = CMD_ALLOC_VN;
    cmd_valid = 1'b1;
    @(posedge clk);
    cmd_valid = 1'b0;

    wait (ack == 1'b1);
    $display("CMD_ALLOC_VN ACK received at time %t", $time);
    @(posedge clk);

    // Read and print BV memory contents
    begin : read_bv
        integer bv_count, idx;
        // Read count from bv_mem[0]
        @(negedge clk);
        bv_addr = 0;
        bv_ren = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        bv_ren = 1'b0;
        @(posedge clk); #1;
        bv_count = bv_rdata;
        $display("BV count = %0d", bv_count);
        for (idx = 1; idx <= bv_count; idx = idx + 1) begin
            @(negedge clk);
            bv_addr = idx;
            bv_ren = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            bv_ren = 1'b0;
            @(posedge clk); #1;
            $display("  BV[%0d] (VN%0d): %08b", idx, idx-1, bv_rdata);
        end
    end

    cmd = CMD_SEND_A;
    cmd_valid = 1'b1;
    @(posedge clk);
    cmd_valid = 1'b0;

    wait (ack == 1'b1);
    $display("CMD_SEND_A ACK received at time %t", $time);
    @(posedge clk);
    $display("ack signal now %b", ack);


    cmd = CMD_SEND_B;
    cmd_valid = 1'b1;
    @(posedge clk);
    cmd_valid = 1'b0;

    wait (ack == 1'b1);
    $display("CMD_SEND_B ACK received at time %t", $time); 
    @(posedge clk);
    $display("ack signal now %b", ack);   


    $finish;
end








endmodule