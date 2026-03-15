module tb_system_top;

    localparam NUM_MS = 8;
    localparam DATA_W = 16;
    localparam A_ADDR_W = 4;
    localparam B_ADDR_W = 4;
    localparam BV_ADDR_W = 4;

    // Command mapping
    localparam CMD_INIT          = 3'd0;
    localparam CMD_VN_ALLOC      = 3'd1;
    localparam CMD_MN_CFG_STAT   = 3'd2;
    localparam CMD_SEND_A        = 3'd3;
    localparam CMD_MN_CFG_STREAM = 3'd4;
    localparam CMD_SEND_B        = 3'd5;

    reg clk;
    reg rst_n;
    reg [2:0] cmd;
    reg cmd_valid;

    wire config_en;
    reg  config_rdy;
    wire [NUM_MS-1:0] config_data;

    wire data_en;
    reg  data_rdy;
    wire [DATA_W-1:0] data_data;

    wire ms_config_en;
    reg  ms_config_rdy;
    wire [(20*NUM_MS)-1:0] ms_config_data;

    wire ack;

    // DUT
    system_top #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W),
        .A_INIT_FILE("mem_A_2x2.mem"),
        .B_INIT_FILE("mem_B_2x2.mem")
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
        .ms_config_en(ms_config_en),
        .ms_config_rdy(ms_config_rdy),
        .ms_config_data(ms_config_data),
        .ack(ack)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin #100000; $display("TIMEOUT"); $finish; end

    // Print Config word
    task print_ms_config;
        integer s;
        reg [19:0] cfg;
        begin
            for (s = 0; s < NUM_MS; s = s + 1) begin
                cfg = ms_config_data[s*20 +: 20];
                $display("  MS[%0d]: state=%04b  psum=%0d", s, cfg[3:0], cfg[19:4]);
            end
        end
    endtask

    // Packet printing
    always @(posedge clk) begin
        if (config_en && data_en && config_rdy && data_rdy) begin
            $display("Time %0t: Packet -> Val=%0d  Mask=%08b", $time, data_data, config_data);
        end
    end

    // MS Config printing
    always @(posedge clk) begin
        if (ms_config_en && ms_config_rdy) begin
            $display("Time %0t: MS Config Broadcast:", $time);
            print_ms_config();
        end
    end

    // Helper task to run a command
    task run_cmd;
        input [2:0] c;
        input [127:0] msg;
        begin
            $display("\n--- %0s ---", msg);
            @(posedge clk);
            cmd = c;
            cmd_valid = 1'b1;
            @(posedge clk);
            cmd_valid = 1'b0;
            cmd = CMD_INIT;
            wait(ack == 1'b1);
            @(posedge clk);
            $display("ACK received for %0s", msg);
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        cmd = CMD_INIT;
        cmd_valid = 0;
        config_rdy = 1;
        data_rdy = 1;
        ms_config_rdy = 1;
        #20; rst_n = 1;
        
        run_cmd(CMD_VN_ALLOC,      "VN ALLOCATION");
        run_cmd(CMD_MN_CFG_STAT,   "MN CONFIG STATIONARY");
        run_cmd(CMD_SEND_A,        "SEND MATRIX A");
        run_cmd(CMD_MN_CFG_STREAM, "MN CONFIG STREAMING");
        run_cmd(CMD_SEND_B,        "SEND MATRIX B");

        $display("\n=== FULL SEQUENCE COMPLETED ===");
        $finish;
    end

endmodule
