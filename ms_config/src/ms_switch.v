module mkMN_MultiplierSwitch (
    input wire CLK,
    input wire RST_N,
    
    input wire [15:0] dataPorts_putIptData_newIptData,
    input wire EN_dataPorts_putIptData,
    output wire RDY_dataPorts_putIptData,
    
    output reg [15:0] dataPorts_getPSum,
    input wire EN_dataPorts_getPSum,
    output wire RDY_dataPorts_getPSum,
    
    input wire [19:0] controlPorts_putNewConfig_newConfig,
    input wire EN_controlPorts_putNewConfig,
    output wire RDY_controlPorts_putNewConfig
);

    localparam [3:0] STATE_IDLE = 4'b0000;
    localparam [3:0] STATE_FILL_STATIONARY = 4'b0001;
    localparam [3:0] STATE_MULT_STREAMING = 4'b0010;
    
    reg [3:0] current_state;
    reg [15:0] psum_counter;
    reg [15:0] stationary_value;
    reg [31:0] mult_result;
    reg result_valid;
    
    wire [3:0] config_state = controlPorts_putNewConfig_newConfig[19:16];
    wire [15:0] config_psum = controlPorts_putNewConfig_newConfig[15:0];
    
    assign RDY_dataPorts_putIptData = 1'b1;
    assign RDY_dataPorts_getPSum = result_valid;
    assign RDY_controlPorts_putNewConfig = 1'b1;
    
    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            current_state <= STATE_IDLE;
            psum_counter <= 16'b0;
            stationary_value <= 16'b0;
            mult_result <= 32'b0;
            result_valid <= 1'b0;
            dataPorts_getPSum <= 16'b0;
        end 
        else begin
            
            // Clear valid when result is read
            if (EN_dataPorts_getPSum && result_valid) begin
                dataPorts_getPSum <= mult_result[15:0];
                result_valid <= 1'b0;
            end
            
            // Handle configuration
            if (EN_controlPorts_putNewConfig) begin
                current_state <= config_state;
                psum_counter <= config_psum;
                result_valid <= 1'b0;
            end
            
            // State machine
            case (current_state)
            
                STATE_IDLE: begin
                end
                
                STATE_FILL_STATIONARY: begin
                    if (EN_dataPorts_putIptData) begin
                        stationary_value <= dataPorts_putIptData_newIptData;
                    end
                end
                
                STATE_MULT_STREAMING: begin
                    if (EN_dataPorts_putIptData && psum_counter > 0) begin
                        mult_result <= stationary_value * dataPorts_putIptData_newIptData;
                        result_valid <= 1'b1;
                        psum_counter <= psum_counter - 1;
                    end
                end
                
            endcase
        end
    end

endmodule