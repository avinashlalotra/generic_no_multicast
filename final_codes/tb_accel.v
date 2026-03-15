module tb_accel;

    localparam NUM_MS = 8;
    localparam DATA_W = 16;
    localparam A_ADDR_W = 10;
    localparam B_ADDR_W = 10;
    localparam BV_ADDR_W = 10;

    // Command mapping
    localparam CMD_INIT          = 3'd0;
    localparam CMD_VN_ALLOC      = 3'd1;
    localparam CMD_MN_CFG_STAT   = 3'd2;
    localparam CMD_SEND_A        = 3'd3;
    localparam CMD_MN_CFG_STREAM = 3'd4;
    localparam CMD_SEND_B        = 3'd5;
    localparam CMD_RN_CONFIG     = 3'd6;
    localparam CMD_FULL_RUN      = 3'd7;

    reg clk;
    reg rst_n;
    reg [2:0] cmd;
    reg cmd_valid;

    // External RN Config (now internal to controller)
    // removed defunct ports

    // Final output stream
    wire [15:0] output_data;
    reg output_en;
    wire output_rdy;

    wire isEmpty;
    wire RDY_isEmpty;

    wire ack;

    // Probes to internal signals for matching user's TB behavior
    // These probe the controller's internal wires inside mkAccelerator
    wire config_en     = dut.ctrl$config_en;
    wire data_en       = dut.ctrl$data_en;
    wire [7:0] config_data = dut.ctrl$config_data;
    wire [15:0] data_data  = dut.ctrl$data_data;
    wire ms_config_en  = dut.ctrl$ms_config_en;
    wire [(20*NUM_MS)-1:0] ms_config_data = dut.ctrl$ms_config_data;

    // DUT
    mkAccelerator #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W),
        .A_INIT_FILE("matrices/mem_A_2x4.mem"),
        .B_INIT_FILE("matrices/mem_B_4x2.mem")
    ) dut (
        .CLK(clk),
        .RST_N(rst_n),
        .cmd(cmd),
        .cmd_valid(cmd_valid),
        .ack(ack),
        .output_data(output_data),
        .output_en(output_en),
        .output_rdy(output_rdy),
        .isEmpty(isEmpty),
        .RDY_isEmpty(RDY_isEmpty)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin #1000000; $display("TIMEOUT"); $finish; end

    // Print Config word
    task print_ms_config;
        integer s;
        reg [19:0] word;
        begin
            for (s = 0; s < NUM_MS; s = s + 1) begin
                word = ms_config_data[s*20 +: 20];
                $display("  MS[%0d]: state=%04b  payload=%0d", s, word[19:16], word[15:0]);
            end
        end
    endtask

    // Packet printing
    always @(posedge clk) begin
        if (config_en && data_en) begin
            $display("Time %0t: Controller Packet -> Val=%0d  Mask=%08b", $time, data_data, config_data);
        end
    end

    // MS Config printing
    always @(posedge clk) begin
        if (ms_config_en) begin
            $display("Time %0t: MS Config Broadcast:", $time);
            print_ms_config();
        end
    end
    
    // Final result printing with handshake
    integer result_count = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            output_en <= 1'b0;
            result_count <= 0;
        end else begin
            if (output_rdy && !output_en) begin
                output_en <= 1'b1; // Pulse ready to consume
                $display("Time %0d: [RESULT %0d] ACCELERATOR FINAL RESULT -> %0d", $time, result_count, output_data);
                
                // Write to result file
                res_file = $fopen("results_8x8.txt", "a");
                if (res_file) begin
                    $fdisplay(res_file, "%d", output_data);
                    $fclose(res_file);
                end

                result_count <= result_count + 1;
            end else begin
                output_en <= 1'b0;
            end
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

    integer batch;
    integer total_vns;
    integer batch_vns;
    integer num_batches;
    integer M, K, N;
    integer res_file;

    initial begin
        res_file = $fopen("results_8x8.txt", "w");
        $fclose(res_file);
        rst_n = 0;
        cmd = CMD_INIT;
        // Initialize
        cmd_valid = 0;
        // output_en now handled by always block
        #20; rst_n = 1;
        
        // Let's assume M, K, N are known for the loop (or read them if we want to be fancy)
        // For the current test (8x8 * 8x8), M=8, K=8, N=8
        M = 8; K = 8; N = 8;
        total_vns = M * N;
        batch_vns = NUM_MS / K;
        num_batches = (total_vns + batch_vns - 1) / batch_vns;

        $display("\n=== STARTING AUTOMATED FULL RUN ===");
        run_cmd(CMD_FULL_RUN, "FULL ACCELERATOR RUN");

        $display("\n=== VERIFYING RESULT MEMORY C ===");
        M = dut.mem_C.mem[0];
        N = dut.mem_C.mem[1];
        $display("M = %d, N = %d", M, N);
        for (batch = 0; batch < M*N; batch = batch + 1) begin
            $display("mem_C[%0d] = %d", batch + 2, dut.mem_C.mem[batch + 2]);
        end

        $display("\n=== FULL SEQUENCE COMPLETED ===");
         #100;
       

        $finish;
    end

endmodule
