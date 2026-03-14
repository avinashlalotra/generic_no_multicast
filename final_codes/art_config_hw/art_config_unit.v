module art_config_unit #(
    parameter NUM_MS = 8,
    parameter BV_ADDR_W = 4
)(
    input wire clk,
    input wire rst_n,

    // Command interface
    input wire cmd_valid,
    output reg ack,

    // BV memory interface
    output reg [BV_ADDR_W-1:0] bv_addr,
    output reg bv_ren,
    input  wire [NUM_MS-1:0] bv_rdata,

    // ART Configuration Output
    output reg [20:0] rn_config
);

    // FSM States
    localparam S_IDLE       = 3'd0;
    localparam S_READ_CNT   = 3'd1;
    localparam S_CAP_CNT    = 3'd2;
    localparam S_READ_BV    = 3'd3;
    localparam S_CAP_BV     = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0] state;
    reg [31:0] vn_count;
    reg [31:0] bv_idx;

    // Internal 21-bit config accumulation
    reg [20:0] config_accum;

    // Helper function to count bits in a range
    function automatic [3:0] count_bits;
        input [7:0] data;
        input [2:0] start_idx;
        input [2:0] end_idx;
        integer i;
        begin
            count_bits = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if (i >= start_idx && i <= end_idx) begin
                    if (data[i]) count_bits = count_bits + 1;
                end
            end
        end
    endfunction

    // Total bits in a BV
    function automatic [3:0] total_bits;
        input [7:0] data;
        integer i;
        begin
            total_bits = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if (data[i]) total_bits = total_bits + 1;
            end
        end
    endfunction

    // Switch logic generator
    function automatic [2:0] get_switch_cfg;
        input [7:0] bv;
        input [2:0] l_start, l_end;
        input [2:0] r_start, r_end;
        reg [3:0] cL, cR, cT;
        reg [1:0] mode;
        reg genOut;
        begin
            cL = count_bits(bv, l_start, l_end);
            cR = count_bits(bv, r_start, r_end);
            cT = total_bits(bv);

            if (cL > 0 && cR > 0) mode = 2'b01; 
            else if (cL > 0)      mode = 2'b10; 
            else if (cR > 0)      mode = 2'b11; 
            else                  mode = 2'b00; 

            genOut = ( (cL + cR) == cT ) && (cT > 0);
            get_switch_cfg = {mode, genOut};
        end
    endfunction

    // DblRS logic generator
    function automatic [5:0] get_dbl_cfg;
        input [7:0] bv;
        reg [2:0] cfgL, cfgR;
        begin
            cfgL = get_switch_cfg(bv, 3'd2, 3'd2, 3'd3, 3'd3);
            cfgR = get_switch_cfg(bv, 3'd4, 3'd4, 3'd5, 3'd5);
            get_dbl_cfg = {cfgL[2:1], cfgR[2:1], cfgL[0], cfgR[0]};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            ack <= 1'b0;
            bv_addr <= 0;
            bv_ren <= 1'b0;
            vn_count <= 0;
            bv_idx <= 0;
            config_accum <= 21'b0;
            rn_config <= 21'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    ack <= 1'b0;
                    if (cmd_valid) begin
                        config_accum <= 21'b0;
                        bv_addr <= 0;
                        bv_ren <= 1'b1;
                        state <= S_READ_CNT;
                    end
                end

                S_READ_CNT: begin
                    bv_ren <= 1'b0;
                    state <= S_CAP_CNT;
                end

                S_CAP_CNT: begin
                    vn_count <= bv_rdata;
                    bv_idx <= 1;
                    if (bv_rdata > 0) begin
                        bv_addr <= 1;
                        bv_ren <= 1'b1;
                        state <= S_READ_BV;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_READ_BV: begin
                    bv_ren <= 1'b0;
                    state <= S_CAP_BV;
                end

                S_CAP_BV: begin
                    // Process BV for current VN
                    begin : process_vn
                        reg [2:0] cS4, cS3, cS2, cS1, cS0;
                        reg [5:0] cD0;
                        reg [20:0] vn_config;
                        reg [3:0] total;
                        
                        total = total_bits(bv_rdata);

                        // Level 0
                        cS4 = get_switch_cfg(bv_rdata, 3'd6, 3'd6, 3'd7, 3'd7);
                        cS3 = get_switch_cfg(bv_rdata, 3'd0, 3'd0, 3'd1, 3'd1);
                        cD0 = get_dbl_cfg(bv_rdata); 
                        
                        // Level 1
                        cS1 = get_switch_cfg(bv_rdata, 3'd0, 3'd1, 3'd2, 3'd3);
                        cS2 = get_switch_cfg(bv_rdata, 3'd4, 3'd5, 3'd6, 3'd7);
                        
                        // Level 2 (Root)
                        cS0 = get_switch_cfg(bv_rdata, 3'd0, 3'd3, 3'd4, 3'd7);
                        
                        if (cS3[0] || cD0[1]) begin
                            cS1 = 3'b000;
                            cS0 = 3'b000;
                        end
                        if (cD0[0] || cS4[0]) begin
                            cS2 = 3'b000;
                            cS0 = 3'b000;
                        end
                        if (cS1[0] || cS2[0]) begin
                            cS0 = 3'b000;
                        end

                        vn_config = {cS4, cS3, cS2, cS1, cS0, cD0};
                        config_accum <= config_accum | vn_config;
                    end

                    if (bv_idx < vn_count) begin
                        bv_idx <= bv_idx + 1;
                        bv_addr <= bv_idx[BV_ADDR_W-1:0] + 1;
                        bv_ren <= 1'b1;
                        state <= S_READ_BV;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    rn_config <= config_accum;
                    ack <= 1'b1;
                    if (!cmd_valid) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
