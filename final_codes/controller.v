module system_top #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4,
    parameter BV_ADDR_W = 4,
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

    // Command Decoder
    always @(*) begin
        pbg_cmd = 2'b00;
        pbg_cmd_valid = 1'b0;
        mnc_cmd = 2'b00;
        mnc_cmd_valid = 1'b0;

        if (cmd_valid) begin
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
        end else if (cmd_valid) begin
            if (cmd == 3'd1 || cmd == 3'd3 || cmd == 3'd5) last_cmd_target <= 2'd0;
            else if (cmd == 3'd2 || cmd == 3'd4) last_cmd_target <= 2'd1;
            else if (cmd == 3'd6) last_cmd_target <= 2'd2;
        end
    end

    // Combinatorial Target for immediate memory access
    wire [1:0] current_target = (cmd_valid) ? ( (cmd == 3'd1 || cmd == 3'd3 || cmd == 3'd5) ? 2'd0 :
                                                (cmd == 3'd2 || cmd == 3'd4)               ? 2'd1 :
                                                (cmd == 3'd6)                               ? 2'd2 : last_cmd_target )
                                            : last_cmd_target;

    assign ack = (last_cmd_target == 2'd1) ? mnc_ack : 
                 (last_cmd_target == 2'd2) ? rnc_ack : pbg_ack;

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
    parameter BV_ADDR_W = 4
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
                    active_mask <= active_mask | bv_rdata;
                    if (bv_idx < num_vns) begin
                        bv_idx  <= bv_idx + 1;
                        bv_addr <= bv_idx[BV_ADDR_W-1:0] + 1;
                        bv_ren  <= 1'b1;
                        state   <= S_READ_BV;
                    end else begin
                        state <= S_EMIT_CFG;
                    end
                end

                // Build and emit the (20*NUM_MS)-bit config word
                S_EMIT_CFG: begin
                    ms_config_en <= 1'b1;
                    begin : build_cfg
                        integer s;
                        reg [19:0] cfg;
                        for (s = 0; s < NUM_MS; s = s + 1) begin
                            if (active_mask[s]) begin
                                if (is_streaming)
                                    cfg = {STATE_MULT_STREAMING,16'd1};
                                else
                                    cfg = {STATE_FILL_STATIONARY,16'd0};
                            end else begin
                                cfg = {STATE_IDLE, 16'd0};
                            end
                            ms_config_data[s*20 +: 20] <= cfg;
                        end
                    end
                    state <= S_ACK;
                end

                S_ACK: begin
                    ms_config_en <= 1'b0;
                    ack          <= 1'b1;
                    state        <= S_IDLE;
                end
            endcase
        end
    end

endmodule

module path_bit_gen_top #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4,
    parameter BV_ADDR_W = 4,
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

        .ack(ack)
    );

endmodule



module scheduler_wrapper #(
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4,
    parameter BV_ADDR_W = 4
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

        .ack(ack)
    );

    assign config_en = a_pkt_valid | b_pkt_valid;
    assign data_en   = a_pkt_valid | b_pkt_valid;

    assign config_data = a_pkt_valid ? a_pkt_mask : (b_pkt_valid ? b_pkt_mask : {NUM_MS{1'b0}});
    assign data_data   = a_pkt_valid ? a_pkt_value : (b_pkt_valid ? b_pkt_value : {DATA_W{1'b0}});

endmodule

module simple_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4,
    parameter INIT_FILE = ""
)(
    input wire clk,
    input wire ren,
    input wire [ADDR_W-1:0] addr,
    output reg [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[addr];
        end
    end
endmodule
// Dual-port simple memory: 1 write port + 1 read port
module simple_mem_dp #(
    parameter DATA_W = 32,
    parameter ADDR_W = 4
)(
    input wire clk,

    // Write port
    input wire wen,
    input wire [ADDR_W-1:0] waddr,
    input wire [DATA_W-1:0] wdata,

    // Read port
    input wire ren,
    input wire [ADDR_W-1:0] raddr,
    output reg [DATA_W-1:0] rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    always @(posedge clk) begin
        if (ren) begin
            rdata <= mem[raddr];
        end
    end
endmodule

module packet_scheduler #(
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4,
    parameter BV_ADDR_W = 4
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

    output reg ack
);

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

    // Loop counters
    reg [31:0] i, j, t;
    reg [31:0] vn_idx;

    reg valid_req;
    reg is_b_phase;

    // Drain counter for pipeline flush
    reg [2:0] drain_cnt;

    wire stall = (a_pkt_valid | b_pkt_valid) & !out_ready;
    wire advance = !stall;

    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            dim_M      <= 0;
            dim_K      <= 0;
            dim_N      <= 0;
            i          <= 0;
            j          <= 0;
            t          <= 0;
            vn_idx     <= 0;
            valid_req  <= 1'b0;
            is_b_phase <= 1'b0;
            drain_cnt  <= 0;
            bv_wen     <= 1'b0;
            bv_waddr   <= 0;
            bv_wdata   <= 0;
            ack        <= 1'b0;
        end else if (advance) begin
            valid_req <= 1'b0;
            bv_wen    <= 1'b0;
            ack       <= 1'b0;
            case (state)
                // ---------------------------------------------------------
                IDLE: begin
                    if (cmd_valid) begin
                        case (cmd)
                            CMD_ALLOC_VN: begin
                                state <= READ_M;
                            end
                            CMD_SEND_A: begin
                                state      <= RUN_A;
                                i          <= 0;
                                j          <= 0;
                                t          <= 0;
                                valid_req  <= 1'b1;
                                is_b_phase <= 1'b0;
                            end
                            CMD_SEND_B: begin
                                state      <= RUN_B;
                                i          <= 0;
                                j          <= 0;
                                t          <= 0;
                                valid_req  <= 1'b1;
                                is_b_phase <= 1'b1;
                            end
                            default: ; // CMD_IDLE: stay
                        endcase
                    end
                end

                // ---------------------------------------------------------
                // Dimension reading: READ_M -> READ_K_A -> READ_K_B -> READ_N -> WAIT_DIM -> GEN_BV
                //
                // Timing (memory has 1-cycle read latency):
                //   READ_M:   issue a_addr=0, b_addr=0
                //   READ_K_A: issue a_addr=1, b_addr=1 ; capture a_data=M
                //   READ_K_B: (no new reads)            ; capture a_data=K
                //   READ_N:   (no new reads)            ; capture b_data=K (verify)
                //   WAIT_DIM: (no new reads)            ; capture b_data=N
                // ---------------------------------------------------------
                READ_M: begin
                    state <= READ_K_A;
                end
                READ_K_A: begin
                    dim_M <= a_data;
                    state <= READ_K_B;
                end
                READ_K_B: begin
                    dim_K <= a_data;
                    state <= READ_N;
                end
                READ_N: begin
                    state <= WAIT_DIM;
                end
                WAIT_DIM: begin
                    dim_N  <= b_data;
                    vn_idx <= 0;
                    state  <= GEN_BV;
                end

                // ---------------------------------------------------------
                // Generate bitvectors: write [count, bv0, bv1, ...] to bv_mem
                // ---------------------------------------------------------
                GEN_BV: begin
                    if (vn_idx == 0) begin
                        // Write count = M*N to bv_mem[0]
                        bv_wen   <= 1'b1;
                        bv_waddr <= 0;
                        bv_wdata <= dim_M * dim_N;
                        vn_idx   <= 1;
                    end else if (vn_idx <= dim_M * dim_N) begin
                        // Write BV for VN (vn_idx-1): K consecutive bits at position (vn_idx-1)*K
                        bv_wen   <= 1'b1;
                        bv_waddr <= vn_idx[BV_ADDR_W-1:0];
                        bv_wdata <= (({{(NUM_MS-1){1'b0}}, 1'b1} << dim_K) - 1) << ((vn_idx - 1) * dim_K);
                        vn_idx   <= vn_idx + 1;
                    end else begin
                        bv_wen <= 1'b0;
                        state  <= ACK_ST;
                    end
                end

                // ---------------------------------------------------------
                // RUN_A / RUN_B: Send matrix packets
                // Uses runtime dim_M, dim_K, dim_N
                // ---------------------------------------------------------
                RUN_A, RUN_B: begin
                    valid_req <= 1'b1;
                    if (t == dim_K - 1) begin
                        t <= 0;
                        if (i == dim_M - 1) begin
                            i <= 0;
                            if (j == dim_N - 1) begin
                                j         <= 0;
                                valid_req <= 1'b0;
                                state     <= DRAIN;
                                drain_cnt <= 3'd3; // Wait for pipeline to flush
                            end else begin
                                j <= j + 1;
                            end
                        end else begin
                            i <= i + 1;
                        end
                    end else begin
                        t <= t + 1;
                    end
                end

                // ---------------------------------------------------------
                // DRAIN: Wait for pipeline-delayed packets to clear
                // ---------------------------------------------------------
                DRAIN: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= ACK_ST;
                    end
                end

                // ---------------------------------------------------------
                ACK_ST: begin
                    ack   <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Memory Address and Read Enables
    // =========================================================================
    always @(*) begin
        a_ren  = 1'b0;
        b_ren  = 1'b0;
        a_addr = 0;
        b_addr = 0;

        case (state)
            READ_M: begin
                a_ren  = 1'b1;
                a_addr = 0;  // Read M from mem_A[0]
                b_ren  = 1'b1;
                b_addr = 0;  // Read K from mem_B[0]
            end
            READ_K_A: begin
                a_ren  = 1'b1;
                a_addr = 1;  // Read K from mem_A[1]
                b_ren  = 1'b1;
                b_addr = 1;  // Read N from mem_B[1]
            end

            default: begin
                // RUN_A / RUN_B: element reads (+2 to skip dimension header)
                if (valid_req && advance) begin
                    if (!is_b_phase) begin
                        a_ren  = 1'b1;
                        a_addr = i * dim_K + t + 2;
                    end else begin
                        b_ren  = 1'b1;
                        b_addr = j * dim_K + t + 2;
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
    reg [31:0] i_d, j_d, t_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_req_d  <= 1'b0;
            is_b_phase_d <= 1'b0;
            i_d <= 0;
            j_d <= 0;
            t_d <= 0;
        end else if (advance) begin
            valid_req_d  <= valid_req;
            is_b_phase_d <= is_b_phase;
            i_d <= i;
            j_d <= j;
            t_d <= t;
        end
    end

    wire [31:0] ms_index = ((i_d * dim_N + j_d) * dim_K) + t_d;
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
            if (valid_req_d) begin
                if (!is_b_phase_d) begin
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


