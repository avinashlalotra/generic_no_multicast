module art_config_gen_generic #(
    parameter NUM_MS = 8,
    parameter BV_ADDR_W = 4
)(
    input wire clk,
    input wire rst_n,

    // Trigger
    input wire start,
    output reg done,

    // BV memory interface
    output reg [BV_ADDR_W-1:0] bv_addr,
    output reg bv_ren,
    input  wire [NUM_MS-1:0] bv_rdata,

    // ART Configuration Output (Flat bitstream)
    // Width is 3 bits per switch * (NUM_MS - 1)
    output reg [3*(NUM_MS-1)-1:0] rn_config
);

    localparam NUM_SWITCHES = NUM_MS - 1;
    localparam LEVELS = $clog2(NUM_MS);

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

    // Internal accumulation
    reg [3*NUM_SWITCHES-1:0] config_accum;

    // Helper to count ones in a bitmask
    function automatic [15:0] count_ones;
        input [NUM_MS-1:0] val;
        integer i;
        begin
            count_ones = 0;
            for (i = 0; i < NUM_MS; i = i + 1) begin
                if (val[i]) count_ones = count_ones + 1;
            end
        end
    endfunction

    // Logic to calculate configuration for a single bit-vector
    // We'll use a combinatorial block that looks at all switches
    reg [3*NUM_SWITCHES-1:0] cur_bv_config;
    
    always @(*) begin
        integer l, s, i;
        integer sw_ptr;
        integer total_bits;
        reg [NUM_MS-1:0] l_mask, r_mask;
        integer cL, cR, cT;
        reg [NUM_SWITCHES-1:0] is_peak_candidate;
        reg [2:0] sw_cfg;
        
        sw_ptr = 0;
        total_bits = count_ones(bv_rdata);
        cur_bv_config = 0;
        is_peak_candidate = 0;

        // Pass 1: Mode and Peak Candidate
        for (l = 0; l < LEVELS; l = l + 1) begin
            integer switches_at_level;
            integer span;
            integer half_span;
            
            switches_at_level = NUM_MS >> (l + 1);
            span = (1 << (l + 1));
            half_span = (1 << l);

            for (s = 0; s < switches_at_level; s = s + 1) begin
                l_mask = get_l_mask(l, s);
                r_mask = get_r_mask(l, s);

                cL = count_ones(bv_rdata & l_mask);
                cR = count_ones(bv_rdata & r_mask);
                cT = cL + cR;

                sw_cfg = 3'b000;
                if (cL > 0 && cR > 0)      sw_cfg[2:1] = 2'b01; // ADD
                else if (cL > 0)           sw_cfg[2:1] = 2'b10; // FLOW_L
                else if (cR > 0)           sw_cfg[2:1] = 2'b11; // FLOW_R
                else                       sw_cfg[2:1] = 2'b00; // IDLE

                is_peak_candidate[sw_ptr] = (cT == total_bits) && (total_bits > 0);
                sw_cfg[0] = is_peak_candidate[sw_ptr];
                
                cur_bv_config[3*sw_ptr +: 3] = sw_cfg;
                sw_ptr = sw_ptr + 1;
            end
        end

        // Pass 2: Ancestor refinement
        sw_ptr = 0;
        for (l = 0; l < LEVELS; l = l + 1) begin
            integer switches_at_level;
            switches_at_level = NUM_MS >> (l + 1);
            for (s = 0; s < switches_at_level; s = s + 1) begin
                if (l > 0) begin
                    cL = count_ones(bv_rdata & get_l_mask(l, s));
                    cR = count_ones(bv_rdata & get_r_mask(l, s));
                    
                    if (cL == total_bits || cR == total_bits) begin
                        cur_bv_config[3*sw_ptr +: 3] = 3'b000;
                    end
                end
                sw_ptr = sw_ptr + 1;
            end
        end
    end

    // Helper masks (repeated logic for clarity in combinatorial block)
    function automatic [NUM_MS-1:0] get_l_mask;
        input integer l, s;
        integer i, span, half_span;
        begin
            span = (1 << (l + 1));
            half_span = (1 << l);
            get_l_mask = 0;
            for (i = 0; i < NUM_MS; i = i + 1) begin
                if (i >= s*span && i < s*span + half_span) get_l_mask[i] = 1;
            end
        end
    endfunction

    function automatic [NUM_MS-1:0] get_r_mask;
        input integer l, s;
        integer i, span, half_span;
        begin
            span = (1 << (l + 1));
            half_span = (1 << l);
            get_r_mask = 0;
            for (i = 0; i < NUM_MS; i = i + 1) begin
                if (i >= s*span + half_span && i < (s+1)*span) get_r_mask[i] = 1;
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            bv_addr <= 0;
            bv_ren <= 1'b0;
            vn_count <= 0;
            bv_idx <= 0;
            config_accum <= 0;
            rn_config <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        config_accum <= 0;
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
                    // OR the combinatorial result into accum
                    config_accum <= config_accum | cur_bv_config;
                    
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
                    done <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
