module system_top #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 10,
    parameter B_ADDR_W = 10,
    parameter BV_ADDR_W = 10,
    parameter A_INIT_FILE = "",
    parameter B_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,

    // Unified Command Interface
    input wire [2:0] cmd,
    input wire cmd_valid,

    // Packet streams (from path_bit_gen)
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,

    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,

    // MS config output (from mn_config)
    output wire ms_config_en,
    input  wire ms_config_rdy,
    output wire [(20*NUM_MS)-1:0] ms_config_data,

    // RN config output (from art_config_unit)
    output wire rn_config_en,
    input  wire rn_config_rdy,
    output wire [20:0] rn_config_data,
    output wire [31:0] k_probe,

    // Result Memory C Interface
    output reg mem_c_wen,
    output reg [B_ADDR_W-1:0] mem_c_waddr,
    output reg [DATA_W-1:0] mem_c_wdata,

    // Status from Datapath
    input wire isEmpty,

    // Output from ART
    input  wire [DATA_W-1:0] art_output_data,
    input  wire art_output_rdy,
    output reg  art_output_en,

    output wire ack
);

    // Command mapping and routing
    reg [1:0] pbg_cmd;
    reg pbg_cmd_valid;
    reg [1:0] mnc_cmd;
    reg mnc_cmd_valid;
    reg rnc_cmd_valid;

    wire pbg_ack;
    wire mnc_ack;
    wire rnc_ack;

    // Master State Machine for CMD_FULL_RUN
    localparam M_IDLE           = 4'd0;
    localparam M_WRITE_M        = 4'd1;
    localparam M_WRITE_N        = 4'd2;
    localparam M_ALLOC          = 4'd3;
    localparam M_RN_CONFIG      = 4'd4;
    localparam M_MN_CFG_STAT    = 4'd5;
    localparam M_SEND_A         = 4'd6;
    localparam M_MN_CFG_STRM    = 4'd7;
    localparam M_SEND_B         = 4'd8;
    localparam M_WAIT_EMPTY     = 4'd9;
    localparam M_CHECK_DONE     = 4'd10;
    localparam M_ACK            = 4'd11;

    reg [3:0] master_state, next_master_state;
    reg full_run_active;
    reg [31:0] results_captured;
    reg [31:0] results_target;
    reg [B_ADDR_W-1:0] next_c_addr;

    // Derived dimensions from packet_scheduler
    wire [31:0] sched_M = pbg.wrapper.sched.dim_M;
    wire [31:0] sched_N = pbg.wrapper.sched.dim_N;
    wire [31:0] total_results = sched_M * sched_N;

    // Command Decoder / Internal Sequencer
    always @(*) begin
        next_master_state = master_state;
        pbg_cmd = 2'b00;
        pbg_cmd_valid = 1'b0;
        mnc_cmd = 2'b00;
        mnc_cmd_valid = 1'b0;
        rnc_cmd_valid = 1'b0;

        if (full_run_active) begin
            case (master_state)
                M_ALLOC: begin
                    pbg_cmd = 2'b01;
                    pbg_cmd_valid = 1'b1;
                end
                M_RN_CONFIG: begin
                    rnc_cmd_valid = 1'b1;
                end
                M_MN_CFG_STAT: begin
                    mnc_cmd = 2'b01;
                    mnc_cmd_valid = 1'b1;
                end
                M_SEND_A: begin
                    pbg_cmd = 2'b10;
                    pbg_cmd_valid = 1'b1;
                end
                M_MN_CFG_STRM: begin
                    mnc_cmd = 2'b10;
                    mnc_cmd_valid = 1'b1;
                end
                M_SEND_B: begin
                    pbg_cmd = 2'b11;
                    pbg_cmd_valid = 1'b1;
                end
                default: ;
            endcase
        end else if (cmd_valid) begin
            case (cmd)
                3'd1: begin // VN_ALLOC
                    pbg_cmd = 2'b01; 
                    pbg_cmd_valid = 1'b1;
                end
                3'd2: begin // MN_CFG_STAT
                    mnc_cmd = 2'b01;
                    mnc_cmd_valid = 1'b1;
                end
                3'd3: begin // SEND_A
                    pbg_cmd = 2'b10;
                    pbg_cmd_valid = 1'b1;
                end
                3'd4: begin // MN_CFG_STREAM
                    mnc_cmd = 2'b10;
                    mnc_cmd_valid = 1'b1;
                end
                3'd5: begin // SEND_B
                    pbg_cmd = 2'b11;
                    pbg_cmd_valid = 1'b1;
                end
                3'd6: begin // RN_CONFIG
                    rnc_cmd_valid = 1'b1;
                end
                default: ; // IDLE or reserved
            endcase
        end
    end

    reg [1:0] last_cmd_target; // 0:PBG, 1:MNC, 2:RNC
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_cmd_target <= 2'd0;
            master_state <= M_IDLE;
            full_run_active <= 1'b0;
            next_c_addr <= 0;
            results_captured <= 0;
            mem_c_wen <= 1'b0;
            mem_c_waddr <= 0;
            mem_c_wdata <= 0;
            art_output_en <= 1'b0;
        end else begin
            mem_c_wen <= 1'b0;
            art_output_en <= 1'b0;

            // Manual command tracking
            if (cmd_valid && !full_run_active) begin
                if (cmd == 3'd1 || cmd == 3'd3 || cmd == 3'd5) last_cmd_target <= 2'd0;
                else if (cmd == 3'd2 || cmd == 3'd4) last_cmd_target <= 2'd1;
                else if (cmd == 3'd6) last_cmd_target <= 2'd2;
                
                if (cmd == 3'b111) begin // FULL_RUN
                    full_run_active <= 1'b1;
                    master_state <= M_ALLOC; // Dimensions will be loaded in M_ALLOC if first time
                    next_c_addr <= 0;
                    results_captured <= 0;
                end
            end

            // Result capture (autonomous)
            if (art_output_rdy && art_output_en) begin
                mem_c_wen <= 1'b1;
                mem_c_waddr <= next_c_addr;
                mem_c_wdata <= art_output_data;
                next_c_addr <= next_c_addr + 1;
                results_captured <= results_captured + 1;
                $display("Time %0d: [CTRL] Captured result %0d -> mem_C[%0d] = %0d", $time, results_captured, next_c_addr, art_output_data);
            end
            // Capture only in Send B or Wait Empty phases
            // Pulse art_output_en to consume one result at a time
            art_output_en <= art_output_rdy && !art_output_en && (master_state == M_SEND_B || master_state == M_WAIT_EMPTY);

            // Master State Machine
            if (full_run_active) begin
                case (master_state)
                    M_ALLOC: begin
                        if (pbg_ack) begin
                            results_target <= (pbg.wrapper.sched.current_batch + 1) * pbg.wrapper.sched.batch_vns;
                            // If first batch, write dimensions
                            if (next_c_addr == 0) begin
                                master_state <= M_WRITE_M;
                            end else begin
                                master_state <= M_RN_CONFIG;
                            end
                        end
                    end
                    M_WRITE_M: begin
                        mem_c_wen <= 1'b1;
                        mem_c_waddr <= 0;
                        mem_c_wdata <= sched_M[DATA_W-1:0];
                        next_c_addr <= 1;
                        next_master_state <= M_WRITE_N;
                    end
                    M_WRITE_N: begin
                        mem_c_wen <= 1'b1;
                        mem_c_waddr <= 1;
                        mem_c_wdata <= sched_N[DATA_W-1:0];
                        next_c_addr <= 2;
                        next_master_state <= M_RN_CONFIG;
                    end
                    M_RN_CONFIG: begin
                        if (rnc_ack) next_master_state <= M_MN_CFG_STAT;
                    end
                    M_MN_CFG_STAT: begin
                        if (mnc_ack) next_master_state <= M_SEND_A;
                    end
                    M_SEND_A: begin
                        if (pbg_ack) next_master_state <= M_MN_CFG_STRM;
                    end
                    M_MN_CFG_STRM: begin
                        if (mnc_ack) next_master_state <= M_SEND_B;
                    end
                    M_SEND_B: begin
                        if (pbg_ack) next_master_state <= M_WAIT_EMPTY;
                    end
                    M_WAIT_EMPTY: begin
                        // Wait for results of current batch OR DN to be empty
                        if (results_captured >= results_target || results_captured >= total_results) begin
                            if (isEmpty) begin // DN isEmpty
                                next_master_state <= M_CHECK_DONE;
                            end
                        end
                    end
                    M_CHECK_DONE: begin
                        // Is this the last batch?
                        // pbg.wrapper.sched.dims_loaded being cleared means pbg saw last batch
                        if (!pbg.wrapper.sched.dims_loaded) begin
                            next_master_state <= M_ACK;
                        end else begin
                            // Reset counters for next batch if needed
                            next_master_state <= M_ALLOC;
                        end
                    end
                    M_ACK: begin
                        full_run_active <= 1'b0;
                        $display("Time %0d: [FULL_RUN] FINISHED. Total captured: %d", $time, results_captured);
                        next_master_state <= M_IDLE;
                    end
                    default: ;
                endcase
                if (master_state != next_master_state) begin
                    $display("Time %0d: [MASTER] %s -> %s (captured=%0d)", $time,
                             (master_state == M_IDLE) ? "M_IDLE" : (master_state == M_ALLOC) ? "M_ALLOC" : (master_state == M_WRITE_M) ? "M_WRITE_M" : (master_state == M_WRITE_N) ? "M_WRITE_N" : (master_state == M_RN_CONFIG) ? "M_RN_CONFIG" : (master_state == M_MN_CFG_STAT) ? "M_MN_CFG_STAT" : (master_state == M_SEND_A) ? "M_SEND_A" : (master_state == M_MN_CFG_STRM) ? "M_MN_CFG_STRM" : (master_state == M_SEND_B) ? "M_SEND_B" : (master_state == M_WAIT_EMPTY) ? "M_WAIT_EMPTY" : (master_state == M_CHECK_DONE) ? "M_CHECK_DONE" : "M_ACK",
                             (next_master_state == M_IDLE) ? "M_IDLE" : (next_master_state == M_ALLOC) ? "M_ALLOC" : (next_master_state == M_WRITE_M) ? "M_WRITE_M" : (next_master_state == M_WRITE_N) ? "M_WRITE_N" : (next_master_state == M_RN_CONFIG) ? "M_RN_CONFIG" : (next_master_state == M_MN_CFG_STAT) ? "M_MN_CFG_STAT" : (next_master_state == M_SEND_A) ? "M_SEND_A" : (next_master_state == M_MN_CFG_STRM) ? "M_MN_CFG_STRM" : (next_master_state == M_SEND_B) ? "M_SEND_B" : (next_master_state == M_WAIT_EMPTY) ? "M_WAIT_EMPTY" : (next_master_state == M_CHECK_DONE) ? "M_CHECK_DONE" : "M_ACK",
                             results_captured);
                    master_state <= next_master_state;
                end
            end
        end
    end

    // Combinatorial Target for immediate memory access
    wire [1:0] current_target = (full_run_active) ? ( (master_state == M_ALLOC || master_state == M_SEND_A || master_state == M_SEND_B) ? 2'd0 :
                                                     (master_state == M_MN_CFG_STAT || master_state == M_MN_CFG_STRM) ? 2'd1 :
                                                     (master_state == M_RN_CONFIG) ? 2'd2 : 2'd0 ) :
                                (cmd_valid) ? ( (cmd == 3'd1 || cmd == 3'd3 || cmd == 3'd5) ? 2'd0 :
                                                (cmd == 3'd2 || cmd == 3'd4)               ? 2'd1 :
                                                (cmd == 3'd6)                               ? 2'd2 : last_cmd_target )
                                            : last_cmd_target;

    assign ack = (full_run_active) ? (master_state == M_ACK) :
                 (last_cmd_target == 2'd1) ? mnc_ack :
                 (last_cmd_target == 2'd2) ? rnc_ack : pbg_ack;

    wire [31:0] k_val;
    wire [31:0] pbg_current_batch, pbg_batch_vns, pbg_total_vns;
    assign k_probe = k_val;

    // BV memory interface sharing
    wire [BV_ADDR_W-1:0] pbg_bv_addr;
    wire pbg_bv_ren;
    wire [NUM_MS-1:0] pbg_bv_rdata;

    wire [BV_ADDR_W-1:0] mnc_bv_addr;
    wire mnc_bv_ren;

    wire [BV_ADDR_W-1:0] rnc_bv_addr;
    wire rnc_bv_ren;

    wire [BV_ADDR_W-1:0] shared_bv_addr = (current_target == 2'd1) ? mnc_bv_addr :
                                         (current_target == 2'd2) ? rnc_bv_addr : pbg_bv_addr;
    wire shared_bv_ren = (current_target == 2'd1) ? mnc_bv_ren :
                        (current_target == 2'd2) ? rnc_bv_ren : pbg_bv_ren;

    // Instantiate Path Bit Gen (includes memories and BV memory)
    path_bit_gen_top #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W),
        .A_INIT_FILE(A_INIT_FILE),
        .B_INIT_FILE(B_INIT_FILE)
    ) pbg (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(pbg_cmd),
        .cmd_valid(pbg_cmd_valid),
        .config_en(config_en),
        .config_rdy(config_rdy),
        .config_data(config_data),
        .data_en(data_en),
        .data_rdy(data_rdy),
        .data_data(data_data),
        // Connect shared BV read port
        .bv_addr(shared_bv_addr),
        .bv_ren(shared_bv_ren),
        .bv_rdata(pbg_bv_rdata),
        .k_out(k_val),
        .current_batch(pbg_current_batch),
        .batch_vns(pbg_batch_vns),
        .total_vns(pbg_total_vns),
        .ack(pbg_ack)
    );

    // For now pbg_bv_addr/ren are unused by the top module itself
    assign pbg_bv_addr = 0;
    assign pbg_bv_ren = 1'b0;

    // Instantiate MN Config
    mn_config #(
        .NUM_MS(NUM_MS),
        .BV_ADDR_W(BV_ADDR_W)
    ) mnc (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(mnc_cmd),
        .cmd_valid(mnc_cmd_valid),
        .bv_addr(mnc_bv_addr),
        .bv_ren(mnc_bv_ren),
        .bv_rdata(pbg_bv_rdata),
        .ms_config_en(ms_config_en),
        .ms_config_rdy(ms_config_rdy),
        .ms_config_data(ms_config_data),
        .k_val(k_val),
        .ack(mnc_ack)
    );

    // Instantiate RN Config (ART Config)
    art_config_unit #(
        .NUM_MS(NUM_MS),
        .BV_ADDR_W(BV_ADDR_W)
    ) rnc (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(rnc_cmd_valid),
        .ack(rnc_ack),
        .bv_addr(rnc_bv_addr),
        .bv_ren(rnc_bv_ren),
        .bv_rdata(pbg_bv_rdata),
        .rn_config(rn_config_data)
    );

    // Handshake for rn_config (simplified for now as ART config is stationary once set)
    assign rn_config_en = rnc_ack; // Simple: once done, enable it a bit like STATIONARY config

endmodule

module mn_config #(
    parameter NUM_MS = 8,
    parameter BV_ADDR_W = 10
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire [1:0] cmd,
    input wire cmd_valid,

    // BV memory read port
    output reg [BV_ADDR_W-1:0] bv_addr,
    output reg bv_ren,
    input  wire [NUM_MS-1:0] bv_rdata,

    // MS config output (broadcast to all MS)
    output reg ms_config_en,
    input  wire ms_config_rdy,
    output reg [(20*NUM_MS)-1:0] ms_config_data,
    input  wire [31:0] k_val,

    output reg ack
);

    // Command encoding
    localparam CMD_IDLE           = 2'b00;
    localparam CMD_CFG_STATIONARY = 2'b01;
    localparam CMD_CFG_STREAMING  = 2'b10;

    // MS state encoding (lower 4 bits of 20-bit config)
    localparam [3:0] STATE_IDLE            = 4'b0000;
    localparam [3:0] STATE_FILL_STATIONARY = 4'b0001;
    localparam [3:0] STATE_MULT_STREAMING  = 4'b0010;

    // State machine
    //   Pipeline: issue read -> wait 1 cycle -> capture rdata
    localparam [2:0] S_IDLE         = 3'd0;
    localparam [2:0] S_READ_BV_CNT  = 3'd1;  // Issue read for bv_mem[0]
    localparam [2:0] S_CAP_BV_CNT   = 3'd2;  // Capture bv_mem[0] = count
    localparam [2:0] S_READ_BV      = 3'd3;  // Issue read for bv_mem[bv_idx]
    localparam [2:0] S_CAP_BV       = 3'd4;  // Capture BV, OR into active_mask
    localparam [2:0] S_EMIT_CFG     = 3'd5;  // Build and emit config word
    localparam [2:0] S_ACK          = 3'd6;

    reg [2:0] state;
    reg is_streaming;
    reg [31:0] num_vns;
    reg [31:0] bv_idx;
    reg [NUM_MS-1:0] active_mask;

    wire stall = ms_config_en & !ms_config_rdy;
    wire advance = !stall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            is_streaming   <= 1'b0;
            num_vns        <= 0;
            bv_idx         <= 0;
            active_mask    <= 0;
            bv_ren         <= 1'b0;
            bv_addr        <= 0;
            ms_config_en   <= 1'b0;
            ms_config_data <= 0;
            ack            <= 1'b0;
        end else if (advance) begin
            bv_ren <= 1'b0;
            ack    <= 1'b0;
            case (state)
                S_IDLE: begin
                    ms_config_en <= 1'b0;
                    if (cmd_valid && cmd != CMD_IDLE) begin
                        is_streaming <= (cmd == CMD_CFG_STREAMING);
                        active_mask  <= 0;
                        // Issue read for bv_mem[0]
                        bv_addr <= 0;
                        bv_ren  <= 1'b1;
                        state   <= S_READ_BV_CNT;
                        $display("Time %0d: [MN_CFG] STARTING. is_streaming=%b", $time, (cmd == CMD_CFG_STREAMING));
                    end
                end

                // Wait for memory to respond to addr=0
                S_READ_BV_CNT: begin
                    state <= S_CAP_BV_CNT;
                end

                // Capture count from bv_rdata
                S_CAP_BV_CNT: begin
                    num_vns <= bv_rdata;
                    bv_idx  <= 1;
                    if (bv_rdata > 0) begin
                        // Issue read for bv_mem[1]
                        bv_addr <= 1;
                        bv_ren  <= 1'b1;
                        state   <= S_READ_BV;
                    end else begin
                        state <= S_EMIT_CFG;
                    end
                end

                // Wait for BV read to respond
                S_READ_BV: begin
                    state <= S_CAP_BV;
                end

                // Capture BV, accumulate mask, issue next read or emit
                S_CAP_BV: begin
                    if (advance) begin
                        active_mask <= active_mask | bv_rdata;
                        $display("Time %0d: [MN_CFG] Cap BV idx %0d: %08h -> ActiveMask %08h", $time, bv_idx, bv_rdata, active_mask | bv_rdata);
                        if (bv_idx < num_vns) begin
                            bv_idx  <= bv_idx + 1;
                            bv_addr <= bv_idx[BV_ADDR_W-1:0] + 1;
                            bv_ren  <= 1'b1;
                            state   <= S_READ_BV;
                        end else begin
                            state   <= S_EMIT_CFG;
                        end
                    end
                end

                // Build and emit the (20*NUM_MS)-bit config word
                S_EMIT_CFG: begin
                    ms_config_en <= 1'b1;
                    begin : build_cfg
                        integer s;
                        reg [159:0] tmp_cfg;
                        tmp_cfg = 0;
                        for (s = 0; s < NUM_MS; s = s + 1) begin
                            if (active_mask[s]) begin
                                tmp_cfg[s*20 +: 20] = {(is_streaming ? STATE_MULT_STREAMING : STATE_FILL_STATIONARY), 16'h0001};
                            end else begin
                                tmp_cfg[s*20 +: 20] = {STATE_IDLE, 16'h0000};
                            end
                        end
                        ms_config_data <= tmp_cfg;
                    end
                    state <= S_ACK;
                end

                S_ACK: begin
                    ms_config_en <= 1'b0;
                    ack          <= 1'b1;
                    if (!cmd_valid) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule

module path_bit_gen_top #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 10,
    parameter B_ADDR_W = 10,
    parameter BV_ADDR_W = 10,
    parameter A_INIT_FILE = "",
    parameter B_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire [1:0] cmd,
    input wire cmd_valid,

    // Config packet stream
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,

    // Data packet stream
    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,

    // BV memory read port (external)
    input  wire [BV_ADDR_W-1:0] bv_addr,
    input  wire bv_ren,
    output wire [NUM_MS-1:0] bv_rdata,
    output wire [31:0] k_out,
    output wire [31:0] current_batch,
    output wire [31:0] batch_vns,
    output wire [31:0] total_vns,
    output wire ack
);

    // Internal memory interface wires
    wire [A_ADDR_W-1:0] a_addr;
    wire a_ren;
    wire [DATA_W-1:0] a_data;

    wire [B_ADDR_W-1:0] b_addr;
    wire b_ren;
    wire [DATA_W-1:0] b_data;

    // BV write port from scheduler
    wire [BV_ADDR_W-1:0] bv_waddr;
    wire bv_wen;
    wire [NUM_MS-1:0] bv_wdata;

    // Instantiate matrix memories
    // Scheduler handles addressing directly (including +2 offset for elements)
    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(A_ADDR_W),
        .INIT_FILE(A_INIT_FILE)
    ) mem_A (
        .clk(clk),
        .ren(a_ren),
        .addr(a_addr),
        .rdata(a_data)
    );

    simple_mem #(
        .DATA_W(DATA_W),
        .ADDR_W(B_ADDR_W),
        .INIT_FILE(B_INIT_FILE)
    ) mem_B (
        .clk(clk),
        .ren(b_ren),
        .addr(b_addr),
        .rdata(b_data)
    );

    // BV memory: written by scheduler, read externally
    simple_mem_dp #(
        .DATA_W(NUM_MS),
        .ADDR_W(BV_ADDR_W)
    ) bv_mem (
        .clk(clk),
        .wen(bv_wen),
        .waddr(bv_waddr),
        .wdata(bv_wdata),
        .ren(bv_ren),
        .raddr(bv_addr),
        .rdata(bv_rdata)
    );

    // Instantiate scheduler wrapper
    scheduler_wrapper #(
        .NUM_MS(NUM_MS),
        .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W),
        .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W)
    ) wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(cmd),
        .cmd_valid(cmd_valid),

        .a_addr(a_addr),
        .a_ren(a_ren),
        .a_data(a_data),

        .b_addr(b_addr),
        .b_ren(b_ren),
        .b_data(b_data),

        .bv_waddr(bv_waddr),
        .bv_wen(bv_wen),
        .bv_wdata(bv_wdata),

        .config_en(config_en),
        .config_rdy(config_rdy),
        .config_data(config_data),

        .data_en(data_en),
        .data_rdy(data_rdy),
        .data_data(data_data),
        .k_out(k_out),
        .current_batch(current_batch),
        .batch_vns(batch_vns),
        .total_vns(total_vns),
        .ack(ack)
    );

endmodule



module scheduler_wrapper #(
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 10,
    parameter B_ADDR_W = 10,
    parameter BV_ADDR_W = 10
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire [1:0] cmd,
    input wire cmd_valid,

    // Memory interface A
    output wire [A_ADDR_W-1:0] a_addr,
    output wire a_ren,
    input  wire [DATA_W-1:0] a_data,

    // Memory interface B
    output wire [B_ADDR_W-1:0] b_addr,
    output wire b_ren,
    input  wire [DATA_W-1:0] b_data,

    // BV memory write port
    output wire [BV_ADDR_W-1:0] bv_waddr,
    output wire bv_wen,
    output wire [NUM_MS-1:0] bv_wdata,

    // Config packet stream
    output wire config_en,
    input  wire config_rdy,
    output wire [NUM_MS-1:0] config_data,

    // Data packet stream
    output wire data_en,
    input  wire data_rdy,
    output wire [DATA_W-1:0] data_data,

    output wire [31:0] k_out,
    output wire [31:0] current_batch,
    output wire [31:0] batch_vns,
    output wire [31:0] total_vns,
    output wire ack
);

    wire out_ready = config_rdy & data_rdy;

    wire a_pkt_valid;
    wire [DATA_W-1:0] a_pkt_value;
    wire [NUM_MS-1:0] a_pkt_mask;

    wire b_pkt_valid;
    wire [DATA_W-1:0] b_pkt_value;
    wire [NUM_MS-1:0] b_pkt_mask;

    packet_scheduler #(
        .NUM_MS(NUM_MS), .DATA_W(DATA_W),
        .A_ADDR_W(A_ADDR_W), .B_ADDR_W(B_ADDR_W),
        .BV_ADDR_W(BV_ADDR_W)
    ) sched (
        .clk(clk),
        .rst_n(rst_n),
        .cmd(cmd),
        .cmd_valid(cmd_valid),
        .out_ready(out_ready),

        .a_addr(a_addr),
        .a_ren(a_ren),
        .a_data(a_data),

        .b_addr(b_addr),
        .b_ren(b_ren),
        .b_data(b_data),

        .bv_waddr(bv_waddr),
        .bv_wen(bv_wen),
        .bv_wdata(bv_wdata),

        .a_pkt_valid(a_pkt_valid),
        .a_pkt_value(a_pkt_value),
        .a_pkt_mask(a_pkt_mask),

        .b_pkt_valid(b_pkt_valid),
        .b_pkt_value(b_pkt_value),
        .b_pkt_mask(b_pkt_mask),
        .k_out(k_out),
        .current_batch(current_batch),
        .batch_vns(batch_vns),
        .total_vns(total_vns),
        .ack(ack)
    );

    assign config_en = a_pkt_valid | b_pkt_valid;
    assign data_en   = a_pkt_valid | b_pkt_valid;

    assign config_data = a_pkt_valid ? a_pkt_mask : (b_pkt_valid ? b_pkt_mask : {NUM_MS{1'b0}});
    assign data_data   = a_pkt_valid ? a_pkt_value : (b_pkt_valid ? b_pkt_value : {DATA_W{1'b0}});

endmodule

module simple_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 10,
    parameter INIT_FILE = ""
)(
    input wire clk,
    input wire ren,
    input wire [ADDR_W-1:0] addr,
    output wire [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    assign rdata = mem[addr];
endmodule
// Dual-port simple memory: 1 write port + 1 read port
module simple_mem_dp #(
    parameter DATA_W = 32,
    parameter ADDR_W = 10
)(
    input wire clk,

    // Write port
    input wire wen,
    input wire [ADDR_W-1:0] waddr,
    input wire [DATA_W-1:0] wdata,

    // Read port
    input wire ren,
    input wire [ADDR_W-1:0] raddr,
    output wire [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];
endmodule

module packet_scheduler #(
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 10,
    parameter B_ADDR_W = 10,
    parameter BV_ADDR_W = 10
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire [1:0] cmd,
    input wire cmd_valid,

    input wire out_ready,

    // Memory interface A
    output reg [A_ADDR_W-1:0] a_addr,
    output reg a_ren,
    input  wire [DATA_W-1:0] a_data,

    // Memory interface B
    output reg [B_ADDR_W-1:0] b_addr,
    output reg b_ren,
    input  wire [DATA_W-1:0] b_data,

    // BV memory write port
    output reg [BV_ADDR_W-1:0] bv_waddr,
    output reg bv_wen,
    output reg [NUM_MS-1:0] bv_wdata,

    // Packet streams
    output reg a_pkt_valid,
    output reg [DATA_W-1:0] a_pkt_value,
    output reg [NUM_MS-1:0] a_pkt_mask,

    output reg b_pkt_valid,
    output reg [DATA_W-1:0] b_pkt_value,
    output reg [NUM_MS-1:0] b_pkt_mask,

    output reg [31:0] k_out,
    output reg [31:0] current_batch,
    output wire [31:0] batch_vns,
    output wire [31:0] total_vns,
    output reg ack
);

    assign total_vns = dim_M * dim_N;
    assign batch_vns = 1;

    // Command encoding
    localparam CMD_IDLE     = 2'b00;
    localparam CMD_ALLOC_VN = 2'b01;
    localparam CMD_SEND_A   = 2'b10;
    localparam CMD_SEND_B   = 2'b11;

    // State encoding
    localparam [3:0] IDLE       = 4'd0;
    localparam [3:0] READ_M     = 4'd1;
    localparam [3:0] READ_K_A   = 4'd2;
    localparam [3:0] READ_K_B   = 4'd3;
    localparam [3:0] READ_N     = 4'd4;
    localparam [3:0] WAIT_DIM   = 4'd5;
    localparam [3:0] GEN_BV     = 4'd6;
    localparam [3:0] RUN_A      = 4'd7;
    localparam [3:0] RUN_B      = 4'd8;
    localparam [3:0] DRAIN      = 4'd9;   // Wait for pipeline to flush
    localparam [3:0] ACK_ST     = 4'd10;

    reg [3:0] state;

    // Runtime dimensions (read from memory, persist across commands)
    reg [31:0] dim_M, dim_K, dim_N;
    reg dims_loaded;

    // Loop counters
    reg [31:0] vn_idx, t;
    wire [31:0] global_vn = (current_batch * batch_vns) + vn_idx;

    reg valid_req;
    reg is_b_phase;
    reg batch_inc_done;

    // Drain counter for pipeline flush
    reg [7:0] drain_cnt;

    wire stall = (a_pkt_valid | b_pkt_valid) & !out_ready;
    wire advance = !stall;

    // Local variables for logic
    wire [31:0] rem_vns = (total_vns > current_batch * batch_vns) ? (total_vns - current_batch * batch_vns) : 0;

    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            dim_M      <= 0;
            dim_K      <= 0;
            dim_N      <= 0;
            dims_loaded <= 1'b0;
            current_batch <= 0;
            vn_idx     <= 0;
            t          <= 0;
            valid_req  <= 1'b0;
            is_b_phase <= 1'b0;
            batch_inc_done <= 1'b0;
            k_out      <= 0;
            drain_cnt  <= 0;
            bv_wen     <= 1'b0;
            bv_waddr   <= 0;
            bv_wdata   <= 0;
            ack        <= 1'b0;
        end else if (advance) begin
            valid_req <= 1'b0;
            bv_wen    <= 1'b0;
            ack       <= 1'b0;
            k_out     <= dim_K;
            case (state)
                // ---------------------------------------------------------
                IDLE: begin
                    if (cmd_valid) begin
                        case (cmd)
                            CMD_ALLOC_VN: begin
                                if (!dims_loaded) begin
                                    state <= READ_M;
                                    current_batch <= 0;
                                end else begin
                                    state <= GEN_BV;
                                end
                                vn_idx <= 0;
                                t <= 0;
                                batch_inc_done <= 1'b0;
                            end
                            CMD_SEND_A: begin
                                state      <= RUN_A;
                                vn_idx     <= 0;
                                t          <= 0;
                                valid_req  <= 1'b1;
                                is_b_phase <= 1'b0;
                                batch_inc_done <= 1'b0;
                            end
                            CMD_SEND_B: begin
                                state      <= RUN_B;
                                vn_idx     <= 0;
                                t          <= 0;
                                valid_req  <= 1'b1;
                                is_b_phase <= 1'b1;
                                batch_inc_done <= 1'b0;
                            end
                            default: ; // CMD_IDLE: stay
                        endcase
                    end
                end

                READ_M: begin
                    dim_M <= a_data;
                    state <= READ_K_A;
                end
                READ_K_A: begin
                    dim_K <= a_data;
                    state <= READ_K_B;
                end
                READ_K_B: begin
                    dim_N <= b_data;
                    state <= WAIT_DIM;
                end
                WAIT_DIM: begin
                    dims_loaded <= 1'b1;
                    current_batch <= 0;
                    $display("Time %0d: [DIM] Loaded M=%0d, K=%0d, N=%0d", $time, dim_M, dim_K, dim_N);
                    state  <= GEN_BV;
                end

                // ---------------------------------------------------------
                // Generate bitvectors: write [count, bv0, bv1, ...] to bv_mem for CURRENT BATCH
                // ---------------------------------------------------------
                GEN_BV: begin
                    if (vn_idx == 0) begin
                        // Write count of VNs in this batch to bv_mem[0]
                        bv_wen   <= 1'b1;
                        bv_waddr <= 0;
                        bv_wdata <= (rem_vns < batch_vns) ? rem_vns : batch_vns;
                        $display("Time %0d: [SCHED] GEN_BV_WRITE: Addr=0, Data=%0d (batch_vns=%0d, K=%0d)", $time, (rem_vns < batch_vns) ? rem_vns : batch_vns, batch_vns, dim_K);
                        vn_idx   <= 1;
                    end else if (vn_idx <= batch_vns) begin
                        // Write local BV to shared memory
                        if ((vn_idx - 1) < rem_vns) begin
                            bv_wen   <= 1'b1;
                            bv_waddr <= vn_idx[BV_ADDR_W-1:0];
                            bv_wdata <= (({{(NUM_MS-1){1'b0}}, 1'b1} << dim_K) - 1) << ((vn_idx-1) * dim_K);
                            $display("Time %0d: [SCHED] GEN_BV_WRITE: Addr=%0d, Data=%08h (K=%0d)", $time, vn_idx, (({{(NUM_MS-1){1'b0}}, 1'b1} << dim_K) - 1) << ((vn_idx-1) * dim_K), dim_K);
                        end
                        vn_idx   <= vn_idx + 1;
                    end else begin
                        bv_wen <= 1'b0;
                        vn_idx <= 0;
                        state  <= ACK_ST;
                    end
                end

                // ---------------------------------------------------------
                // RUN_A / RUN_B: Send matrix packets for CURRENT BATCH
                // ---------------------------------------------------------
                RUN_A, RUN_B: begin
                    if (global_vn < total_vns) begin
                        valid_req <= 1'b1;
                    end else begin
                        valid_req <= 1'b0;
                    end

                    // Increment counters
                    if (t == 0) $display("Time %0d: [SCHED] Batch %0d Start VN %0d i=%0d j=%0d", $time, current_batch, vn_idx, i_curr, j_curr);
                    $display("Time %0d: [SCHED] t=%0d a_addr=%0d b_addr=%0d", $time, t, a_addr, b_addr);
                    if (t == dim_K - 1) begin
                        t <= 0;
                        if (vn_idx == batch_vns - 1) begin
                            vn_idx    <= 0;
                            valid_req <= 1'b0;
                            state     <= DRAIN;
                            drain_cnt <= 8'd100; // Increased drain for safety
                        end else begin
                            vn_idx <= vn_idx + 1;
                        end
                    end else begin
                        t <= t + 1;
                    end
                end

                DRAIN: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= ACK_ST;
                    end
                end

                ACK_ST: begin
                    if (is_b_phase && !batch_inc_done) begin
                        current_batch <= current_batch + 1;
                        batch_inc_done <= 1'b1;
                        // Reset if all batches done
                        if ((current_batch + 1) * batch_vns >= total_vns) begin
                            dims_loaded <= 1'b0;
                        end
                    end
                    is_b_phase <= 1'b0;
                    vn_idx <= 0;
                    t <= 0;
                    ack   <= 1'b1;
                    if (!cmd_valid) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Memory Address and Read Enables
    // =========================================================================
    wire [31:0] i_curr = global_vn / dim_N;
    wire [31:0] j_curr = global_vn % dim_N;

    always @(*) begin
        a_ren  = 1'b0;
        b_ren  = 1'b0;
        a_addr = 0;
        b_addr = 0;

        case (state)
            READ_M: begin
                a_ren  = 1'b1;
                a_addr = 0;
            end
            READ_K_A: begin
                a_ren  = 1'b1;
                a_addr = 1;
            end
            READ_K_B: begin
                b_ren  = 1'b1;
                b_addr = 1;
            end

            default: begin
                // RUN_A / RUN_B: element reads (+2 to skip dimension header)
                if (valid_req && advance) begin
                    if (!is_b_phase) begin
                        a_ren  = 1'b1;
                        a_addr = i_curr * dim_K + t + 2;
                    end else begin
                        b_ren  = 1'b1;
                        b_addr = j_curr * dim_K + t + 2;
                        if (advance) $display("Time %0d: [ADDR_B] j=%0d K=%0d t=%0d -> Addr=%0d", $time, j_curr, dim_K, t, b_addr);
                    end
                end
            end
        endcase
    end

    // =========================================================================
    // Pipeline registers for packet generation
    // =========================================================================
    reg valid_req_d;
    reg is_b_phase_d;
    reg [31:0] global_vn_d;
    reg [31:0] t_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_req_d   <= 1'b0;
            is_b_phase_d  <= 1'b0;
            global_vn_d   <= 0;
            t_d           <= 0;
        end else if (advance) begin
            valid_req_d   <= valid_req;
            is_b_phase_d  <= is_b_phase;
            global_vn_d   <= global_vn;
            t_d           <= t;
        end
    end

    wire [31:0] ms_index = ((global_vn % batch_vns) * dim_K) + t;
    wire [NUM_MS-1:0] mask_one = 1;
    wire [NUM_MS-1:0] mask_val = mask_one << ms_index;

    // =========================================================================
    // Packet output stage
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_pkt_valid <= 1'b0;
            a_pkt_value <= 0;
            a_pkt_mask  <= 0;

            b_pkt_valid <= 1'b0;
            b_pkt_value <= 0;
            b_pkt_mask  <= 0;
        end else if (advance) begin
            if (valid_req) begin
                if (!is_b_phase) begin
                    a_pkt_valid <= 1'b1;
                    a_pkt_value <= a_data;
                    a_pkt_mask  <= mask_val;

                    b_pkt_valid <= 1'b0;
                    b_pkt_value <= 0;
                    b_pkt_mask  <= 0;
                end else begin
                    a_pkt_valid <= 1'b0;
                    a_pkt_value <= 0;
                    a_pkt_mask  <= 0;

                    b_pkt_valid <= 1'b1;
                    b_pkt_value <= b_data;
                    b_pkt_mask  <= mask_val;
                end
            end else begin
                a_pkt_valid <= 1'b0;
                a_pkt_value <= 0;
                a_pkt_mask  <= 0;

                b_pkt_valid <= 1'b0;
                b_pkt_value <= 0;
                b_pkt_mask  <= 0;
            end
        end
    end

endmodule


