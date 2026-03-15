module tb_path_bit_gen_top;

    localparam NUM_MS = 8;
    localparam DATA_W = 16;
    localparam A_ADDR_W = 2;
    localparam B_ADDR_W = 2;
    localparam BV_ADDR_W = 2;

    // Command encoding
    localparam CMD_IDLE     = 2'b00;
    localparam CMD_ALLOC_VN = 2'b01;
    localparam CMD_SEND_A   = 2'b10;
    localparam CMD_SEND_B   = 2'b11;

    reg clk;
    reg rst_n;
    reg [1:0] cmd;
    reg cmd_valid;

    wire config_en;
    reg config_rdy;
    wire [NUM_MS-1:0] config_data;

    wire data_en;
    reg data_rdy;
    wire [DATA_W-1:0] data_data;

    // BV read port
    reg [BV_ADDR_W-1:0] bv_addr;
    reg bv_ren;
    wire [NUM_MS-1:0] bv_rdata;

    wire ack;

    // Buffers for packets
    reg [DATA_W-1:0] pkt_val_buf [0:63];
    reg [NUM_MS-1:0] pkt_mask_buf [0:63];
    integer pkt_cnt;

    // Instantiate top module
    path_bit_gen_top #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W),
        .A_INIT_FILE("tb/mem_A_2x2.hex"),
        .B_INIT_FILE("tb/mem_B_2x2.hex")
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

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT error. Simulation did not finish.");
        $finish;
    end

    // Randomize ready signals to mock backpressure
    reg [31:0] rand_val;
    always @(posedge clk) begin
        if (!rst_n) begin
            config_rdy <= 1'b0;
            data_rdy <= 1'b0;
        end else begin
            rand_val = $random;
            config_rdy <= (rand_val % 100) < 60;
            data_rdy   <= (rand_val % 100) > 30;
        end
    end

    // Capture output packets
    always @(posedge clk) begin
        if (config_en && data_en && config_rdy && data_rdy) begin
            pkt_val_buf[pkt_cnt] = data_data;
            pkt_mask_buf[pkt_cnt] = config_data;
            pkt_cnt = pkt_cnt + 1;
        end
    end

    // Task to send a command and wait for ack
    task send_cmd;
        input [1:0] c;
        begin
            @(posedge clk);
            cmd = c;
            cmd_valid = 1'b1;
            @(posedge clk);
            cmd_valid = 1'b0;
            cmd = CMD_IDLE;
            @(posedge ack);
            // Wait a few cycles for any pipeline-delayed packets to clear
            repeat(3) @(posedge clk);
        end
    endtask

    // Task to read BV memory at given address
    task read_bv_mem;
        input [BV_ADDR_W-1:0] addr;
        output [NUM_MS-1:0] data;
        begin
            @(negedge clk);    // set signals between clock edges
            bv_addr = addr;
            bv_ren = 1'b1;
            @(posedge clk);    // memory samples addr and ren
            #1;                // small delay for nonblocking rdata to update
            @(negedge clk);
            bv_ren = 1'b0;
            @(posedge clk);    // rdata now holds mem[addr]
            #1;
            data = bv_rdata;
        end
    endtask

    integer idx;
    integer bv_count;
    reg [NUM_MS-1:0] bv_val;
    initial begin
        pkt_cnt = 0;
        cmd = CMD_IDLE;
        cmd_valid = 1'b0;
        bv_addr = 0;
        bv_ren = 1'b0;

        rst_n = 0;
        #20;
        rst_n = 1;
        #10;

        // ===== Phase 1: ALLOC_VN =====
        $display("\n===== ALLOC_VN =====");
        send_cmd(CMD_ALLOC_VN);
        $display("ALLOC_VN completed (ack received)");

        // Read BV count from bv_mem[0]
        read_bv_mem(0, bv_val);
        bv_count = bv_val;
        $display("BV count = %0d", bv_count);

        // Read each BV
        for (idx = 1; idx <= bv_count && idx < (1 << BV_ADDR_W); idx = idx + 1) begin
            read_bv_mem(idx, bv_val);
            $display("  BV[%0d] (VN%0d): %08b", idx, idx-1, bv_val);
        end

        // ===== Phase 2: SEND_A =====
        $display("\n===== SEND_A =====");
        pkt_cnt = 0;
        send_cmd(CMD_SEND_A);
        $display("SEND_A completed (ack received)");
        $display("Captured %0d A packets", pkt_cnt);
        for (idx = 0; idx < pkt_cnt; idx = idx + 1) begin
            $display("  Pkt %0d (A): Val %0d , Mask %08b", idx, pkt_val_buf[idx], pkt_mask_buf[idx]);
        end

        // ===== Phase 3: SEND_B =====
        $display("\n===== SEND_B =====");
        pkt_cnt = 0;
        send_cmd(CMD_SEND_B);
        $display("SEND_B completed (ack received)");
        $display("Captured %0d B packets", pkt_cnt);
        for (idx = 0; idx < pkt_cnt; idx = idx + 1) begin
            $display("  Pkt %0d (B): Val %0d , Mask %08b", idx, pkt_val_buf[idx], pkt_mask_buf[idx]);
        end

        $display("\n--- SIMULATION COMPLETED ---");
        $finish;
    end

endmodule
