module tb_mn_config;

    localparam NUM_MS = 8;
    localparam BV_ADDR_W = 4;

    localparam CMD_IDLE           = 2'b00;
    localparam CMD_CFG_STATIONARY = 2'b01;
    localparam CMD_CFG_STREAMING  = 2'b10;

    reg clk;
    reg rst_n;
    reg [1:0] cmd;
    reg cmd_valid;

    wire [BV_ADDR_W-1:0] bv_addr;
    wire bv_ren;
    wire [NUM_MS-1:0] bv_rdata;

    wire ms_config_en;
    reg  ms_config_rdy;
    wire [(20*NUM_MS)-1:0] ms_config_data;

    wire ack;

    // BV memory (pre-filled for M=2,K=2,N=2)
    simple_mem_dp #(
        .DATA_W(NUM_MS),
        .ADDR_W(BV_ADDR_W)
    ) bv_mem (
        .clk(clk),
        .wen(1'b0), .waddr(0), .wdata(0),
        .ren(bv_ren), .raddr(bv_addr), .rdata(bv_rdata)
    );

    // Pre-fill BV memory
    initial begin
        bv_mem.mem[0] = 4;            // count = 4 VNs
        bv_mem.mem[1] = 8'b00000011;  // VN0: MS 0,1
        bv_mem.mem[2] = 8'b00001100;  // VN1: MS 2,3
        bv_mem.mem[3] = 8'b00110000;  // VN2: MS 4,5
        bv_mem.mem[4] = 8'b11000000;  // VN3: MS 6,7
    end

    // DUT
    mn_config #(
        .NUM_MS(NUM_MS),
        .BV_ADDR_W(BV_ADDR_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(cmd),
        .cmd_valid(cmd_valid),
        .bv_addr(bv_addr),
        .bv_ren(bv_ren),
        .bv_rdata(bv_rdata),
        .ms_config_en(ms_config_en),
        .ms_config_rdy(ms_config_rdy),
        .ms_config_data(ms_config_data),
        .ack(ack)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin #50000; $display("TIMEOUT"); $finish; end

    // Print config when emitted
    always @(posedge clk) begin
        if (ms_config_en && ms_config_rdy) begin
            begin : print_cfg
                integer s;
                reg [19:0] cfg;
                for (s = 0; s < NUM_MS; s = s + 1) begin
                    cfg = ms_config_data[s*20 +: 20];
                    $display("  MS[%0d]: state=%04b  psum=%0d", s, cfg[3:0], cfg[19:4]);
                end
            end
        end
    end

    integer idx;
    initial begin
        rst_n = 0;
        cmd = CMD_IDLE;
        cmd_valid = 0;
        ms_config_rdy = 1'b1;
        #20; rst_n = 1;
        @(posedge clk);

        // CFG_STATIONARY
        $display("\n===== CFG_STATIONARY =====");
        cmd = CMD_CFG_STATIONARY;
        cmd_valid = 1'b1;
        @(posedge clk);
        cmd_valid = 1'b0;
        cmd = CMD_IDLE;
        wait(ack == 1'b1);
        @(posedge clk);
        $display("CFG_STATIONARY ack received");

        // CFG_STREAMING
        $display("\n===== CFG_STREAMING =====");
        cmd = CMD_CFG_STREAMING;
        cmd_valid = 1'b1;
        @(posedge clk);
        cmd_valid = 1'b0;
        cmd = CMD_IDLE;
        wait(ack == 1'b1);
        @(posedge clk);
        $display("CFG_STREAMING ack received");

        $display("\n--- DONE ---");
        $finish;
    end

endmodule
