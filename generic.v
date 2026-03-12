module packet_generator_generic #(
    parameter NUM_MS = 8
)(
    input clk,
    input rst,
    input start,

    input [7:0] M,
    input [7:0] N,
    input [7:0] K,

    input [31:0] B_base_ptr,

    output reg valid,
    output reg [31:0] data,
    output reg [$clog2(NUM_MS)-1:0] pathbits
);

localparam PATHW = $clog2(NUM_MS);

reg [7:0] i;
reg [7:0] j;
reg [7:0] k;
reg [7:0] t;

reg running;

reg [PATHW-1:0] base_ms;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        valid <= 0;
        running <= 0;
        i <= 0;
        j <= 0;
        k <= 0;
        t <= 0;
    end
    else begin

        if(start) begin
            running <= 1;
            i <= 0;
            j <= 0;
            k <= 0;
            t <= 0;
        end

        if(running) begin

            // Column-major B access
            data <= B_base_ptr + (j*K + k);

            // VN → MS allocation
            base_ms = (i*N + j) * K;

            pathbits <= base_ms + t;

            valid <= 1;

            // inner loop across MS of VN
            if(t < K-1) begin
                t <= t + 1;
            end
            else begin
                t <= 0;

                if(i < M-1) begin
                    i <= i + 1;
                end
                else begin
                    i <= 0;

                    if(k < K-1) begin
                        k <= k + 1;
                    end
                    else begin
                        k <= 0;

                        if(j < N-1) begin
                            j <= j + 1;
                        end
                        else begin
                            running <= 0;
                        end
                    end
                end
            end

        end
        else begin
            valid <= 0;
        end

    end
end

endmodule