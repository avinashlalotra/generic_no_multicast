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

    output wire ack
);

    // Command mapping and routing
    reg [1:0] pbg_cmd;
    reg pbg_cmd_valid;
    
    reg [1:0] mnc_cmd;
    reg mnc_cmd_valid;

    wire pbg_ack;
    wire mnc_ack;

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
                default: ; // IDLE or reserved
            endcase
        end
    end

    // Ack Multiplexing
    // We register the target of the last command to select the ack
    reg last_cmd_was_mnc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_cmd_was_mnc <= 1'b0;
        end else if (cmd_valid) begin
            last_cmd_was_mnc <= (cmd == 3'd2 || cmd == 3'd4);
        end
    end

    assign ack = last_cmd_was_mnc ? mnc_ack : pbg_ack;

    // BV memory interface sharing
    wire [BV_ADDR_W-1:0] pbg_bv_addr;
    wire pbg_bv_ren;
    wire [NUM_MS-1:0] pbg_bv_rdata;

    wire [BV_ADDR_W-1:0] mnc_bv_addr;
    wire mnc_bv_ren;

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
        .bv_addr(last_cmd_was_mnc ? mnc_bv_addr : pbg_bv_addr),
        .bv_ren(last_cmd_was_mnc ? mnc_bv_ren : pbg_bv_ren),
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

endmodule
