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
                                    cfg = {16'd1, STATE_MULT_STREAMING};
                                else
                                    cfg = {16'd0, STATE_FILL_STATIONARY};
                            end else begin
                                cfg = {16'd0, STATE_IDLE};
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
