module tb_ms_config_top;

    localparam M = 2;
    localparam K = 1;
    localparam N = 2;
    localparam NUM_MS = 4;
    localparam DATA_W = 32;
    localparam A_ADDR_W = 6;
    localparam B_ADDR_W = 6;

    reg clk;
    reg rst_n;
    reg start;
    
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

    // Instantiate Top Module
    ms_config_top #(
        .M(M),
        .K(K),
        .N(N),
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .A_INIT_FILE("tb/mem_A_2x2.hex"),
        .B_INIT_FILE("tb/mem_B_2x2.hex")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
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
        #10000;
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
            $write("Time %0t: Pkt %0d (%s): Val %0d -> active MS: [ ", $time, pkt_cnt, (pkt_cnt < M*N*K) ? "A" : "B", data_data);
            begin : print_ms
                integer i;
                for (i = 0; i < NUM_MS; i = i + 1) begin
                    if (config_data[i]) $write("%0d ", i);
                end
            end
            $display("]");
            
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
    initial begin
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

        $display("\\n--- SIMULATION COMPLETED (TOP MODULE 2x2, K=1) ---");
        $display("Captured %0d chronological packets\\n", pkt_cnt);
        $finish;
    end

endmodule
