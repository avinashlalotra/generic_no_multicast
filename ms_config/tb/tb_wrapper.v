module tb_wrapper;

    localparam M = 2;
    localparam K = 2;
    localparam N = 2;
    localparam NUM_MS = 8;
    localparam DATA_W = 32;
    localparam A_ADDR_W = 4;
    localparam B_ADDR_W = 4;

    reg clk;
    reg rst_n;
    reg start;

    wire [A_ADDR_W-1:0] a_addr;
    wire a_ren;
    wire [DATA_W-1:0] a_data;

    wire [B_ADDR_W-1:0] b_addr;
    wire b_ren;
    wire [DATA_W-1:0] b_data;
    
    wire config_en;
    reg config_rdy;
    wire [NUM_MS-1:0] config_data;
    
    wire data_en;
    reg data_rdy;
    wire [DATA_W-1:0] data_data;
    
    wire ms_config_en;
    reg ms_config_rdy;
    wire [(20*NUM_MS)-1:0] ms_config_data;
    
    wire done;

    // Buffers for packets
    reg [DATA_W-1:0] pkt_val_buf [0:63];
    reg [NUM_MS-1:0] pkt_mask_buf [0:63];
    integer pkt_cnt;

    // Instantiate memories
    simple_mem #(.DATA_W(DATA_W), .ADDR_W(A_ADDR_W)) mem_A (
        .clk(clk),
        .ren(a_ren),
        .addr(a_addr),
        .rdata(a_data)
    );

    simple_mem #(.DATA_W(DATA_W), .ADDR_W(B_ADDR_W)) mem_B (
        .clk(clk),
        .ren(b_ren),
        .addr(b_addr),
        .rdata(b_data)
    );

    // Instantiate wrapper
    scheduler_wrapper #(
        .M(M),
        .K(K),
        .N(N),
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W)
    ) dut (
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

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("TIMEOUT error. Simulation did not finish.");
        $finish;
    end

    // Randomize ready signals to mock backpressure
    // We will ensure that eventually both are ready together
    reg [31:0] rand_val;
    always @(posedge clk) begin
        if (!rst_n) begin
            config_rdy <= 1'b0;
            data_rdy <= 1'b0;
            ms_config_rdy <= 1'b0;
        end else begin
            rand_val = $random;
            config_rdy <= (rand_val % 100) < 60; // 60% probability of being ready
            data_rdy   <= (rand_val % 100) > 30; // 70% probability of being ready
            ms_config_rdy <= (rand_val % 100) < 80; // 80% probability
        end
    end

    // Capture outputs
    always @(posedge clk) begin
        // The sender puts valid on config_en and data_en.
        // It's consumed only if receiver is ready.
        if (config_en && data_en && config_rdy && data_rdy) begin
            pkt_val_buf[pkt_cnt] = data_data;
            pkt_mask_buf[pkt_cnt] = config_data;
            pkt_cnt = pkt_cnt + 1;
        end
        if (ms_config_en && ms_config_rdy) begin
            $display("Time %0t: MS CONFIG EMITTED: %x", $time, ms_config_data);
        end
    end

    // Initialize & Test
    integer idx;
    initial begin
        // Initialize A matrix
        $readmemh("tb/mem_A.hex", mem_A.mem);
        
        // Initialize B matrix
        $readmemh("tb/mem_B.hex", mem_B.mem);

        pkt_cnt = 0;
        
        rst_n = 0;
        start = 0;
        
        #20;
        rst_n = 1;
        
        #10;
        start = 1;
        #10;
        start = 0;
        
        @(posedge done);
        #40;

        // Print packets
        $display("Captured %0d packets", pkt_cnt);
        for (idx = 0; idx < pkt_cnt; idx = idx + 1) begin
            // Phase A is first 8 packets, Phase B is next 8 packets
            if (idx < M*N*K)
                $display("Pkt %0d (A): Val %0d , Mask %08b", idx, pkt_val_buf[idx], pkt_mask_buf[idx]);
            else
                $display("Pkt %0d (B): Val %0d , Mask %08b", idx, pkt_val_buf[idx], pkt_mask_buf[idx]);
        end

        $finish;
    end

endmodule
