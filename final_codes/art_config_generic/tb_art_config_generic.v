module tb_art_config_generic;

    parameter NUM_MS = 8;
    parameter BV_ADDR_W = 4;

    reg clk;
    reg rst_n;
    reg start;
    wire done;

    wire [BV_ADDR_W-1:0] bv_addr;
    wire bv_ren;
    reg [NUM_MS-1:0] bv_rdata;

    wire [3*(NUM_MS-1)-1:0] rn_config;

    // Mock BV Memory
    reg [NUM_MS-1:0] mem [0:15];

    art_config_gen_generic #(
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
        #1000000;
        $display("TIMEOUT");
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
            $display("\n=== TEST (NUM_MS=%0d): %0s ===", NUM_MS, name);
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

        if (NUM_MS == 8) begin
            // Test Case 1: 2x2 Matrix Pattern
            mem[1] = 8'h03; mem[2] = 8'h0C; mem[3] = 8'h30; mem[4] = 8'hC0;
            run_test(4, "2x2 Disjoint VNs");
        end else if (NUM_MS == 4) begin
            mem[1] = 4'h3; mem[2] = 4'hC;
            run_test(2, "2x1 Disjoint VNs");
        end else if (NUM_MS == 16) begin
            mem[1] = 16'hFFFF;
            run_test(1, "1x16 Full Reduction");
        end

        $display("\nALL TESTS FOR NUM_MS=%0d COMPLETED", NUM_MS);
        #100;
        $finish;
    end

endmodule
