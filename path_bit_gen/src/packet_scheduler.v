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
