module packet_scheduler #(
    parameter M = 2,
    parameter K = 2,
    parameter N = 2,
    parameter NUM_MS = 8,
    parameter DATA_W = 32,
    parameter A_ADDR_W = 4,
    parameter B_ADDR_W = 4
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire out_ready,
    
    // Memory interface A
    output reg [A_ADDR_W-1:0] a_addr,
    output reg a_ren,
    input  wire [DATA_W-1:0] a_data,
    
    // Memory interface B
    output reg [B_ADDR_W-1:0] b_addr,
    output reg b_ren,
    input  wire [DATA_W-1:0] b_data,
    
    // MS Config interface
    output reg ms_config_en,
    input  wire ms_config_rdy,
    output reg [(20*NUM_MS)-1:0] ms_config_data,
    
    // Packet streams
    output reg a_pkt_valid,
    output reg [DATA_W-1:0] a_pkt_value,
    output reg [NUM_MS-1:0] a_pkt_mask,
    
    output reg b_pkt_valid,
    output reg [DATA_W-1:0] b_pkt_value,
    output reg [NUM_MS-1:0] b_pkt_mask,
    
    output reg done
);

    localparam [3:0] STATE_FILL_STATIONARY = 4'b0001;
    localparam [3:0] STATE_MULT_STREAMING  = 4'b0010;

    wire stall = ((a_pkt_valid | b_pkt_valid) & !out_ready) | (ms_config_en & !ms_config_rdy);
    wire advance = !stall;

    reg [31:0] i, j, t;
    reg valid_req;
    reg is_b_phase;

    localparam [2:0] IDLE     = 3'b000;
    localparam [2:0] CONFIG_A = 3'b001;
    localparam [2:0] RUN_A    = 3'b010;
    localparam [2:0] DRAIN_A  = 3'b011;
    localparam [2:0] CONFIG_B = 3'b100;
    localparam [2:0] RUN_B    = 3'b101;
    localparam [2:0] DRAIN_B  = 3'b110;
    localparam [2:0] DONE_ST  = 3'b111;

    reg [2:0] state;

    wire [19:0] cfg_stat = {STATE_FILL_STATIONARY, 16'd0};
    wire [19:0] cfg_strm = {STATE_MULT_STREAMING, 16'd1}; // psum=1 as per user request

    reg [2:0] drain_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            i <= 0;
            j <= 0;
            t <= 0;
            drain_cnt <= 0;
            valid_req <= 1'b0;
            is_b_phase <= 1'b0;
            ms_config_en <= 1'b0;
            ms_config_data <= 0;
        end else if (advance) begin
            valid_req <= 1'b0;
            ms_config_en <= 1'b0; // Default off, asserted only when needed
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= CONFIG_A;
                        i <= 0;
                        j <= 0;
                        t <= 0;
                        valid_req <= 1'b0;
                        is_b_phase <= 1'b0;
                        ms_config_en <= 1'b1;
                        ms_config_data <= {NUM_MS{cfg_stat}};
                    end
                end
                CONFIG_A: begin
                    state <= RUN_A;
                    valid_req <= 1'b1;
                    is_b_phase <= 1'b0;
                end
                RUN_A, RUN_B: begin
                    valid_req <= 1'b1;
                    if (t == K - 1) begin
                        t <= 0;
                        if (i == M - 1) begin
                            i <= 0;
                            if (j == N - 1) begin
                                j <= 0;
                                if (state == RUN_A) begin
                                    state <= DRAIN_A;
                                    valid_req <= 1'b0;
                                    is_b_phase <= 1'b0;
                                    drain_cnt <= 3'd2; // Wait for pipeline to drain
                                end else begin
                                    state <= DRAIN_B;
                                    valid_req <= 1'b0;
                                    is_b_phase <= 1'b1;
                                    drain_cnt <= 3'd2;
                                end
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
                DRAIN_A: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= CONFIG_B;
                        ms_config_en <= 1'b1;
                        ms_config_data <= {NUM_MS{cfg_strm}};
                    end
                end
                CONFIG_B: begin
                    state <= RUN_B;
                    valid_req <= 1'b1;
                    is_b_phase <= 1'b1;
                end
                DRAIN_B: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= DONE_ST;
                    end
                end
                DONE_ST: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Memory Address and Read Enables
    always @(*) begin
        if (valid_req && advance) begin
            if (!is_b_phase) begin
                a_ren  = 1'b1;
                b_ren  = 1'b0;
                a_addr = i * K + t;
                b_addr = 0;
            end else begin
                a_ren  = 1'b0;
                b_ren  = 1'b1;
                a_addr = 0;
                b_addr = j * K + t;
            end
        end else begin
            a_ren  = 1'b0;
            b_ren  = 1'b0;
            a_addr = 0;
            b_addr = 0;
        end
    end

    reg valid_req_d;
    reg is_b_phase_d;
    reg [31:0] i_d, j_d, t_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_req_d <= 1'b0;
            is_b_phase_d <= 1'b0;
            i_d <= 0;
            j_d <= 0;
            t_d <= 0;
        end else if (advance) begin
            valid_req_d <= valid_req;
            is_b_phase_d <= is_b_phase;
            i_d <= i;
            j_d <= j;
            t_d <= t;
        end
    end

    wire [31:0] ms_index = ((i_d * N + j_d) * K) + t_d;
    wire [NUM_MS-1:0] mask_one = 1;
    wire [NUM_MS-1:0] mask_val = mask_one << ms_index;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else if (advance) begin
            if (state == DONE_ST) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
