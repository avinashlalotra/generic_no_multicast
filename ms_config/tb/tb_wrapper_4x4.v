module tb_wrapper_4x4;

    localparam M = 4;
    localparam K = 4;
    localparam N = 4;
    localparam NUM_MS = 16;
    localparam DATA_W = 32;
    localparam A_ADDR_W = 6;
    localparam B_ADDR_W = 6;

    reg clk;
    reg rst_n;
    reg start;

    wire [A_ADDR_W-1:0] a_addr;
    wire a_ren;
    wire [DATA_W-1:0] a_data;

    wire [B_ADDR_W-1:0] b_addr;
    wire b_ren;
    wire [DATA_W-1:0] b_data;
    
    wire data_en;
    reg data_rdy;
    wire [DATA_W-1:0] data_data;
    
    wire ms_config_en;
    reg ms_config_rdy;
    wire [(20*NUM_MS)-1:0] ms_config_data;
    
    wire config_en;
    reg config_rdy;
    wire [NUM_MS-1:0] config_data;
    
    wire done;

    // Buffers for packets
    reg [DATA_W-1:0] pkt_val_buf [0:255];
    reg [NUM_MS-1:0] pkt_mask_buf [0:255];
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
        if (config_en && data_en && config_rdy && data_rdy) begin
            pkt_val_buf[pkt_cnt] = data_data;
            pkt_mask_buf[pkt_cnt] = config_data;
            pkt_cnt = pkt_cnt + 1;
        end
        if (ms_config_en && ms_config_rdy) begin
            if (ms_config_data[19:16] == 4'b0001) begin
               $display("==========================================================");
               $display("Time %0t: MS CONFIG EMITTED: ALL MS -> [STATE: STATIONARY, PSUM: 0]", $time);
               $display("==========================================================");
            end else if (ms_config_data[19:16] == 4'b0010) begin
               $display("==========================================================");
               $display("Time %0t: MS CONFIG EMITTED: ALL MS -> [STATE: STREAMING, PSUM: 1]", $time);
               $display("==========================================================");
            end else begin
               $display("Time %0t: MS CONFIG EMITTED: %x", $time, ms_config_data);
            end
        end
    end

    // Initialize & Test
    integer idx, ms_idx;
    initial begin
        $readmemh("tb/mem_A_4x4.hex", mem_A.mem);
        $readmemh("tb/mem_B_4x4.hex", mem_B.mem);

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

        $display("\n--- FINAL PACKET TRACE (4x4) ---");
        $display("Captured %0d packets\n", pkt_cnt);
        for (idx = 0; idx < pkt_cnt; idx = idx + 1) begin
            $write("Pkt %0d (%s): Val %0d -> active MS: [ ", idx, (idx < M*N*K) ? "A" : "B", pkt_val_buf[idx]);
            for (ms_idx = 0; ms_idx < NUM_MS; ms_idx = ms_idx + 1) begin
                if (pkt_mask_buf[idx][ms_idx]) $write("%0d ", ms_idx);
            end
            $display("]");
        end

        $finish;
    end

endmodule
