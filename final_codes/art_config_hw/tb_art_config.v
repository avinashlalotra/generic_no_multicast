module tb_art_config;

    localparam NUM_MS = 8;
    localparam BV_ADDR_W = 4;

    reg clk;
    reg rst_n;
    reg start;
    wire done;

    wire [BV_ADDR_W-1:0] bv_addr;
    wire bv_ren;
    reg [NUM_MS-1:0] bv_rdata;

    wire [20:0] rn_config;

    // Mock BV Memory
    reg [NUM_MS-1:0] mem [0:15];

    art_config_unit #(
        .NUM_MS(NUM_MS),
        .BV_ADDR_W(BV_ADDR_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .bv_addr(bv_addr),
        .bv_ren(bv_ren),
        .bv_rdata(bv_rdata),
        .rn_config(rn_config)
    );

    initial begin 
        clk = 0; 
        forever #5 clk = ~clk; 
    end

    initial begin
        #500000;
        $display("TIMEOUT at time %t", $time);
        $finish;
    end

    // Sync memory read
    always @(posedge clk) begin
        if (bv_ren) begin
            $display("  [MEM] READ addr %d -> %h", bv_addr, mem[bv_addr]);
            bv_rdata <= mem[bv_addr];
        end
    end

    integer i;
    task run_test;
        input integer vn_cnt;
        input [127:0] name;
        begin
            $display("\n=== TEST: %0s ===", name);
            mem[0] = vn_cnt;
            start = 1;
            @(posedge clk);
            #1; start = 0;
            $display("  [TB] Waiting for DONE...");
            wait(done == 1);
            $display("  [TB] DONE rcvd. Config: %b (%h)", rn_config, rn_config);
            @(posedge clk);
            #10;
        end
    endtask

    initial begin
        $timeformat(-9, 2, " ns", 20);
        rst_n = 0;
        start = 0;
        for (i=0; i<16; i=i+1) mem[i] = 0;
        
        #45; rst_n = 1;
        #50;

        // Test Case 1: 2x2 Matrix Pattern
        mem[1] = 8'h03; mem[2] = 8'h0C; mem[3] = 8'h30; mem[4] = 8'hC0;
        run_test(4, "2x2 Disjoint VNs");

        // Test Case 2: One Single Large VN (size 8)
        mem[1] = 8'hFF;
        run_test(1, "1x8 Full Tree Reduction");

        // Test Case 3: 8 Individual VNs
        for (i=0; i<8; i=i+1) mem[i+1] = (1 << i);
        run_test(8, "8 Streaming VNs");

        $display("\nALL TESTS COMPLETED SUCCESSFULLY");
        #100;
        $finish;
    end

endmodule
