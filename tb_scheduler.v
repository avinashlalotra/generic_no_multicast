module tb_scheduler;

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

    wire a_pkt_valid;
    wire [DATA_W-1:0] a_pkt_value;
    wire [NUM_MS-1:0] a_pkt_mask;

    wire b_pkt_valid;
    wire [DATA_W-1:0] b_pkt_value;
    wire [NUM_MS-1:0] b_pkt_mask;

    wire done;

    // Buffers for packets
    reg [DATA_W-1:0] a_pkt_val_buf [0:63];
    reg [NUM_MS-1:0] a_pkt_mask_buf [0:63];
    integer a_cnt;

    reg [DATA_W-1:0] b_pkt_val_buf [0:63];
    reg [NUM_MS-1:0] b_pkt_mask_buf [0:63];
    integer b_cnt;

    // Instantiate memories
    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(A_ADDR_W)
    ) mem_A (
        .clk(clk),
        .ren(a_ren),
        .addr(a_addr),
        .rdata(a_data)
    );

    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(B_ADDR_W)
    ) mem_B (
        .clk(clk),
        .ren(b_ren),
        .addr(b_addr),
        .rdata(b_data)
    );

    // Instantiate scheduler
    packet_scheduler #(
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
        .a_pkt_valid(a_pkt_valid),
        .a_pkt_value(a_pkt_value),
        .a_pkt_mask(a_pkt_mask),
        .b_pkt_valid(b_pkt_valid),
        .b_pkt_value(b_pkt_value),
        .b_pkt_mask(b_pkt_mask),
        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Timeout watchdog
    initial begin
        #2000;
        $display("TIMEOUT error. Simulation did not finish.");
        $finish;
    end

    // Capture outputs
    always @(posedge clk) begin
        if (a_pkt_valid) begin
            a_pkt_val_buf[a_cnt] = a_pkt_value;
            a_pkt_mask_buf[a_cnt] = a_pkt_mask;
            a_cnt = a_cnt + 1;
        end
        if (b_pkt_valid) begin
            b_pkt_val_buf[b_cnt] = b_pkt_value;
            b_pkt_mask_buf[b_cnt] = b_pkt_mask;
            b_cnt = b_cnt + 1;
        end
    end

    // Initialize & Test
    integer vn_m, vn_n, vn_idx, idx, vn_cnt, base_idx;
    initial begin
        // Initialize A matrix (row-major)
        mem_A.mem[0] = 32'd1;
        mem_A.mem[1] = 32'd2;
        mem_A.mem[2] = 32'd3;
        mem_A.mem[3] = 32'd4;
        
        // Initialize B matrix (col-major)
        mem_B.mem[0] = 32'd5;
        mem_B.mem[1] = 32'd6;
        mem_B.mem[2] = 32'd7;
        mem_B.mem[3] = 32'd8;

        a_cnt = 0;
        b_cnt = 0;
        
        rst_n = 0;
        start = 0;
        
        #20;
        rst_n = 1;
        
        #10;
        start = 1;
        #10;
        start = 0;
        
        @(posedge done);
        #20;

        // Print packets
        vn_cnt = 1;
        for (vn_m = 0; vn_m < M; vn_m = vn_m + 1) begin
            for (vn_n = 0; vn_n < N; vn_n = vn_n + 1) begin
                $display("VN%0d:", vn_cnt);
                base_idx = (vn_n * M + vn_m) * K;
                
                for (idx = 0; idx < K; idx = idx + 1) begin
                    $display("A %0d , %08b", a_pkt_val_buf[base_idx + idx], a_pkt_mask_buf[base_idx + idx]);
                end
                for (idx = 0; idx < K; idx = idx + 1) begin
                    $display("B %0d , %08b", b_pkt_val_buf[base_idx + idx], b_pkt_mask_buf[base_idx + idx]);
                end
                if (vn_cnt < M*N) $display("");
                vn_cnt = vn_cnt + 1;
            end
        end

        $finish;
    end

endmodule
