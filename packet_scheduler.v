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
    
    // Memory interface A
    output reg [A_ADDR_W-1:0] a_addr,
    output reg a_ren,
    input  wire [DATA_W-1:0] a_data,
    
    // Memory interface B
    output reg [B_ADDR_W-1:0] b_addr,
    output reg b_ren,
    input  wire [DATA_W-1:0] b_data,
    
    // Packet streams
    output reg a_pkt_valid,
    output reg [DATA_W-1:0] a_pkt_value,
    output reg [NUM_MS-1:0] a_pkt_mask,
    
    output reg b_pkt_valid,
    output reg [DATA_W-1:0] b_pkt_value,
    output reg [NUM_MS-1:0] b_pkt_mask,
    
    output reg done
);

    reg [31:0] i, j, t;
    reg valid_req;
    reg is_b_phase;

    localparam IDLE    = 2'b00;
    localparam RUN_A   = 2'b01;
    localparam RUN_B   = 2'b10;
    localparam DONE_ST = 2'b11;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            i <= 0;
            j <= 0;
            t <= 0;
            valid_req <= 1'b0;
            is_b_phase <= 1'b0;
        end else begin
            valid_req <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= RUN_A;
                        i <= 0;
                        j <= 0;
                        t <= 0;
                        valid_req <= 1'b1;
                        is_b_phase <= 1'b0;
                    end
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
                                    state <= RUN_B;
                                    is_b_phase <= 1'b1;
                                end else begin
                                    state <= DONE_ST;
                                    valid_req <= 1'b0;
                                    is_b_phase <= 1'b0;
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
                DONE_ST: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always @(*) begin
        if (valid_req) begin
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
        end else begin
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
        end else begin
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

    reg valid_req_dd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_req_dd <= 1'b0;
        end else begin
            valid_req_dd <= valid_req_d;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else begin
            if (valid_req_dd && !valid_req_d) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
