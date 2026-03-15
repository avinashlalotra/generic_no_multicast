//
// Final Top-Level Accelerator Module
// Created: March 14, 2026
//
// This module integrates:
// 1. Controller (system_top from controller.v)
// 2. Datapath (DN -> MN -> ART)
//

`ifdef BSV_ASSIGNMENT_DELAY
`else
  `define BSV_ASSIGNMENT_DELAY
`endif

`ifdef BSV_POSITIVE_RESET
  `define BSV_RESET_VALUE 1'b1
  `define BSV_RESET_EDGE posedge
`else
  `define BSV_RESET_VALUE 1'b0
  `define BSV_RESET_EDGE negedge
`endif

// ================================================================
// Datapath Module: DN -> MN -> ART
// ================================================================
module mkDatapath(CLK,
                  RST_N,

                  isEmpty,
                  RDY_isEmpty,

                  dn_config_data,
                  dn_config_en,
                  dn_config_rdy,

                  mn_config_data,
                  mn_config_numSwitches,
                  mn_config_en,
                  mn_config_rdy,

                  rn_config_data,
                  rn_config_en,
                  rn_config_rdy,

                  input_data,
                  input_en,
                  input_rdy,

                  output_data,
                  output_en,
                  output_rdy);

  input  CLK;
  input  RST_N;

  output isEmpty;
  output RDY_isEmpty;

  // DN Config
  input  [7 : 0] dn_config_data;
  input  dn_config_en;
  output dn_config_rdy;

  // MN Config
  input  [159 : 0] mn_config_data;
  input  [31 : 0] mn_config_numSwitches;
  input  mn_config_en;
  output mn_config_rdy;

  // RN Config
  input  [20 : 0] rn_config_data;
  input  rn_config_en;
  output rn_config_rdy;

  // Input Data (to DN)
  input  [15 : 0] input_data;
  input  input_en;
  output input_rdy;

  // Output Data (from RN)
  output [15 : 0] output_data;
  input  output_en;
  output output_rdy;

  // ================================================================
  // DN (Distribution Network)
  // ================================================================
  wire [15 : 0] dn$output0_data, dn$output1_data, dn$output2_data, dn$output3_data,
                dn$output4_data, dn$output5_data, dn$output6_data, dn$output7_data;
  wire dn$output0_rdy, dn$output1_rdy, dn$output2_rdy, dn$output3_rdy,
       dn$output4_rdy, dn$output5_rdy, dn$output6_rdy, dn$output7_rdy;
  wire dn$output0_en, dn$output1_en, dn$output2_en, dn$output3_en,
       dn$output4_en, dn$output5_en, dn$output6_en, dn$output7_en;

  mkDN_DistributionNetwork dn(.CLK(CLK),
                               .RST_N(RST_N),
                               .isEmpty(isEmpty),
                               .RDY_isEmpty(RDY_isEmpty),
                               .controlPorts_0_putConfig_newConfig(dn_config_data),
                               .EN_controlPorts_0_putConfig(dn_config_en),
                               .RDY_controlPorts_0_putConfig(dn_config_rdy),
                               .inputDataPorts_0_putData_data(input_data),
                               .EN_inputDataPorts_0_putData(input_en),
                               .RDY_inputDataPorts_0_putData(input_rdy),
                               .outputDataPorts_0_getData(dn$output0_data),
                               .RDY_outputDataPorts_0_getData(dn$output0_rdy),
                               .EN_outputDataPorts_0_getData(dn$output0_en),
                               .outputDataPorts_1_getData(dn$output1_data),
                               .RDY_outputDataPorts_1_getData(dn$output1_rdy),
                               .EN_outputDataPorts_1_getData(dn$output1_en),
                               .outputDataPorts_2_getData(dn$output2_data),
                               .RDY_outputDataPorts_2_getData(dn$output2_rdy),
                               .EN_outputDataPorts_2_getData(dn$output2_en),
                               .outputDataPorts_3_getData(dn$output3_data),
                               .RDY_outputDataPorts_3_getData(dn$output3_rdy),
                               .EN_outputDataPorts_3_getData(dn$output3_en),
                               .outputDataPorts_4_getData(dn$output4_data),
                               .RDY_outputDataPorts_4_getData(dn$output4_rdy),
                               .EN_outputDataPorts_4_getData(dn$output4_en),
                               .outputDataPorts_5_getData(dn$output5_data),
                               .RDY_outputDataPorts_5_getData(dn$output5_rdy),
                               .EN_outputDataPorts_5_getData(dn$output5_en),
                               .outputDataPorts_6_getData(dn$output6_data),
                               .RDY_outputDataPorts_6_getData(dn$output6_rdy),
                               .EN_outputDataPorts_6_getData(dn$output6_en),
                               .outputDataPorts_7_getData(dn$output7_data),
                               .RDY_outputDataPorts_7_getData(dn$output7_rdy),
                               .EN_outputDataPorts_7_getData(dn$output7_en));

  // ================================================================
  // MN (Multiplier Network)
  // ================================================================
  wire [15 : 0] mn$output0_data, mn$output1_data, mn$output2_data, mn$output3_data,
                mn$output4_data, mn$output5_data, mn$output6_data, mn$output7_data;
  wire mn$input0_rdy, mn$input1_rdy, mn$input2_rdy, mn$input3_rdy,
       mn$input4_rdy, mn$input5_rdy, mn$input6_rdy, mn$input7_rdy;
  wire mn$output0_rdy, mn$output1_rdy, mn$output2_rdy, mn$output3_rdy,
       mn$output4_rdy, mn$output5_rdy, mn$output6_rdy, mn$output7_rdy;
  wire mn$input0_en, mn$input1_en, mn$input2_en, mn$input3_en,
       mn$input4_en, mn$input5_en, mn$input6_en, mn$input7_en;
  wire mn$output0_en, mn$output1_en, mn$output2_en, mn$output3_en,
       mn$output4_en, mn$output5_en, mn$output6_en, mn$output7_en;

  mkMN_MultiplierNetwork mn(.CLK(CLK),
                            .RST_N(RST_N),
                            .dataPorts_0_putData_data(dn$output0_data),
                            .RDY_dataPorts_0_putData(mn$input0_rdy),
                            .EN_dataPorts_0_putData(mn$input0_en),
                            .dataPorts_0_getData(mn$output0_data),
                            .RDY_dataPorts_0_getData(mn$output0_rdy),
                            .EN_dataPorts_0_getData(mn$output0_en),

                            .dataPorts_1_putData_data(dn$output1_data),
                            .RDY_dataPorts_1_putData(mn$input1_rdy),
                            .EN_dataPorts_1_putData(mn$input1_en),
                            .dataPorts_1_getData(mn$output1_data),
                            .RDY_dataPorts_1_getData(mn$output1_rdy),
                            .EN_dataPorts_1_getData(mn$output1_en),

                            .dataPorts_2_putData_data(dn$output2_data),
                            .RDY_dataPorts_2_putData(mn$input2_rdy),
                            .EN_dataPorts_2_putData(mn$input2_en),
                            .dataPorts_2_getData(mn$output2_data),
                            .RDY_dataPorts_2_getData(mn$output2_rdy),
                            .EN_dataPorts_2_getData(mn$output2_en),

                            .dataPorts_3_putData_data(dn$output3_data),
                            .RDY_dataPorts_3_putData(mn$input3_rdy),
                            .EN_dataPorts_3_putData(mn$input3_en),
                            .dataPorts_3_getData(mn$output3_data),
                            .RDY_dataPorts_3_getData(mn$output3_rdy),
                            .EN_dataPorts_3_getData(mn$output3_en),

                            .dataPorts_4_putData_data(dn$output4_data),
                            .RDY_dataPorts_4_putData(mn$input4_rdy),
                            .EN_dataPorts_4_putData(mn$input4_en),
                            .dataPorts_4_getData(mn$output4_data),
                            .RDY_dataPorts_4_getData(mn$output4_rdy),
                            .EN_dataPorts_4_getData(mn$output4_en),

                            .dataPorts_5_putData_data(dn$output5_data),
                            .RDY_dataPorts_5_putData(mn$input5_rdy),
                            .EN_dataPorts_5_putData(mn$input5_en),
                            .dataPorts_5_getData(mn$output5_data),
                            .RDY_dataPorts_5_getData(mn$output5_rdy),
                            .EN_dataPorts_5_getData(mn$output5_en),

                            .dataPorts_6_putData_data(dn$output6_data),
                            .RDY_dataPorts_6_putData(mn$input6_rdy),
                            .EN_dataPorts_6_putData(mn$input6_en),
                            .dataPorts_6_getData(mn$output6_data),
                            .RDY_dataPorts_6_getData(mn$output6_rdy),
                            .EN_dataPorts_6_getData(mn$output6_en),

                            .dataPorts_7_putData_data(dn$output7_data),
                            .RDY_dataPorts_7_putData(mn$input7_rdy),
                            .EN_dataPorts_7_putData(mn$input7_en),
                            .dataPorts_7_getData(mn$output7_data),
                            .RDY_dataPorts_7_getData(mn$output7_rdy),
                            .EN_dataPorts_7_getData(mn$output7_en),

                            .controlPorts_putConfig_newConfig(mn_config_data),
                            .controlPorts_putConfig_numActualActiveMultSwitches(mn_config_numSwitches),
                            .RDY_controlPorts_putConfig(mn_config_rdy),
                            .EN_controlPorts_putConfig(mn_config_en));

  // DN-to-MN Interconnect
  assign dn$output0_en = dn$output0_rdy && mn$input0_rdy;
  assign mn$input0_en  = dn$output0_rdy && mn$input0_rdy;
  assign dn$output1_en = dn$output1_rdy && mn$input1_rdy;
  assign mn$input1_en  = dn$output1_rdy && mn$input1_rdy;
  assign dn$output2_en = dn$output2_rdy && mn$input2_rdy;
  assign mn$input2_en  = dn$output2_rdy && mn$input2_rdy;
  assign dn$output3_en = dn$output3_rdy && mn$input3_rdy;
  assign mn$input3_en  = dn$output3_rdy && mn$input3_rdy;
  assign dn$output4_en = dn$output4_rdy && mn$input4_rdy;
  assign mn$input4_en  = dn$output4_rdy && mn$input4_rdy;
  assign dn$output5_en = dn$output5_rdy && mn$input5_rdy;
  assign mn$input5_en  = dn$output5_rdy && mn$input5_rdy;
  assign dn$output6_en = dn$output6_rdy && mn$input6_rdy;
  assign mn$input6_en  = dn$output6_rdy && mn$input6_rdy;
  assign dn$output7_en = dn$output7_rdy && mn$input7_rdy;
  assign mn$input7_en  = dn$output7_rdy && mn$input7_rdy;

  // ================================================================
  // RN (Reduction Network / ART)
  // ================================================================
  wire rn$input0_rdy, rn$input1_rdy, rn$input2_rdy, rn$input3_rdy,
       rn$input4_rdy, rn$input5_rdy, rn$input6_rdy, rn$input7_rdy;
  wire rn$input0_en, rn$input1_en, rn$input2_en, rn$input3_en,
       rn$input4_en, rn$input5_en, rn$input6_en, rn$input7_en;

  mkRN_ReductionNetwork rn(.CLK(CLK),
                           .RST_N(RST_N),
                           .inputDataPorts_0_putData_data(mn$output0_data),
                           .RDY_inputDataPorts_0_putData(rn$input0_rdy),
                           .EN_inputDataPorts_0_putData(rn$input0_en),

                           .inputDataPorts_1_putData_data(mn$output1_data),
                           .RDY_inputDataPorts_1_putData(rn$input1_rdy),
                           .EN_inputDataPorts_1_putData(rn$input1_en),

                           .inputDataPorts_2_putData_data(mn$output2_data),
                           .RDY_inputDataPorts_2_putData(rn$input2_rdy),
                           .EN_inputDataPorts_2_putData(rn$input2_en),

                           .inputDataPorts_3_putData_data(mn$output3_data),
                           .RDY_inputDataPorts_3_putData(rn$input3_rdy),
                           .EN_inputDataPorts_3_putData(rn$input3_en),

                           .inputDataPorts_4_putData_data(mn$output4_data),
                           .RDY_inputDataPorts_4_putData(rn$input4_rdy),
                           .EN_inputDataPorts_4_putData(rn$input4_en),

                           .inputDataPorts_5_putData_data(mn$output5_data),
                           .RDY_inputDataPorts_5_putData(rn$input5_rdy),
                           .EN_inputDataPorts_5_putData(rn$input5_en),

                           .inputDataPorts_6_putData_data(mn$output6_data),
                           .RDY_inputDataPorts_6_putData(rn$input6_rdy),
                           .EN_inputDataPorts_6_putData(rn$input6_en),

                           .inputDataPorts_7_putData_data(mn$output7_data),
                           .RDY_inputDataPorts_7_putData(rn$input7_rdy),
                           .EN_inputDataPorts_7_putData(rn$input7_en),

                           .outputDataPorts_0_getData(output_data),
                           .RDY_outputDataPorts_0_getData(output_rdy),
                           .EN_outputDataPorts_0_getData(output_en),

                           .controlPorts_putConfig_newConfig(rn_config_data),
                           .RDY_controlPorts_putConfig(rn_config_rdy),
                           .EN_controlPorts_putConfig(rn_config_en));

  // MN-to-RN Interconnect
  assign mn$output0_en = mn$output0_rdy && rn$input0_rdy;
  assign rn$input0_en  = mn$output0_rdy && rn$input0_rdy;
  assign mn$output1_en = mn$output1_rdy && rn$input1_rdy;
  assign rn$input1_en  = mn$output1_rdy && rn$input1_rdy;
  assign mn$output2_en = mn$output2_rdy && rn$input2_rdy;
  assign rn$input2_en  = mn$output2_rdy && rn$input2_rdy;
  assign mn$output3_en = mn$output3_rdy && rn$input3_rdy;
  assign rn$input3_en  = mn$output3_rdy && rn$input3_rdy;
  assign mn$output4_en = mn$output4_rdy && rn$input4_rdy;
  assign rn$input4_en  = mn$output4_rdy && rn$input4_rdy;
  assign mn$output5_en = mn$output5_rdy && rn$input5_rdy;
  assign rn$input5_en  = mn$output5_rdy && rn$input5_rdy;
  assign mn$output6_en = mn$output6_rdy && rn$input6_rdy;
  assign rn$input6_en  = mn$output6_rdy && rn$input6_rdy;
  assign mn$output7_en = mn$output7_rdy && rn$input7_rdy;
  assign rn$input7_en  = mn$output7_rdy && rn$input7_rdy;

endmodule

// ================================================================
// Final Top Module: mkAccelerator
// ================================================================
module mkAccelerator #(
    parameter NUM_MS = 8,
    parameter DATA_W = 16,
    parameter A_ADDR_W = 10,
    parameter B_ADDR_W = 10,
    parameter BV_ADDR_W = 10,
    parameter A_INIT_FILE = "",
    parameter B_INIT_FILE = ""
)(CLK,
                     RST_N,

                     // Command interface for Controller
                     cmd,
                     cmd_valid,
                     ack,

                     // Final output stream
                     output_data,
                     output_en,
                     output_rdy,

                     isEmpty,
                     RDY_isEmpty);

  input  CLK;
  input  RST_N;

  input  [2 : 0] cmd;
  input  cmd_valid;
  output ack;

  output [15 : 0] output_data;
  input  output_en;
  output output_rdy;

  output isEmpty;
  output RDY_isEmpty;

  // Controller output signals
  wire ctrl$config_en;
  wire ctrl$config_rdy;
  wire [7 : 0] ctrl$config_data;

  wire ctrl$data_en;
  wire ctrl$data_rdy;
  wire [15 : 0] ctrl$data_data;

  wire ctrl$ms_config_en;
  wire ctrl$ms_config_rdy;
  wire [159 : 0] ctrl$ms_config_data;

  wire ctrl$rn_config_en;
  wire ctrl$rn_config_rdy;
  wire [20 : 0] ctrl$rn_config_data;

  // Instantiate Controller (system_top from controller.v)
  system_top #(
    .NUM_MS(NUM_MS),
    .DATA_W(DATA_W),
    .A_ADDR_W(A_ADDR_W),
    .B_ADDR_W(B_ADDR_W),
    .BV_ADDR_W(BV_ADDR_W),
    .A_INIT_FILE("matrices/mem_A_2x2.mem"),
    .B_INIT_FILE("matrices/mem_B_2x2.mem")
  ) controller (
    .clk(CLK),
    .rst_n(RST_N),
    .cmd(cmd),
    .cmd_valid(cmd_valid),
    .config_en(ctrl$config_en),
    .config_rdy(ctrl$config_rdy),
    .config_data(ctrl$config_data),
    .data_en(ctrl$data_en),
    .data_rdy(ctrl$data_rdy),
    .data_data(ctrl$data_data),
    .ms_config_en(ctrl$ms_config_en),
    .ms_config_rdy(ctrl$ms_config_rdy),
    .ms_config_data(ctrl$ms_config_data),
    .rn_config_en(ctrl$rn_config_en),
    .rn_config_rdy(ctrl$rn_config_rdy),
    .rn_config_data(ctrl$rn_config_data),

    // Result Memory Interface
    .mem_c_wen(mem_c_wen),
    .mem_c_waddr(mem_c_waddr),
    .mem_c_wdata(mem_c_wdata),

    // Status
    .isEmpty(isEmpty),

    // Output capture
    .art_output_data(output_data),
    .art_output_rdy(output_rdy),
    .art_output_en(ctrl_art_output_en),

    .ack(ack)
  );

  // Instantiate Datapath
  mkDatapath datapath(
    .CLK(CLK),
    .RST_N(RST_N),
    .isEmpty(isEmpty),
    .RDY_isEmpty(RDY_isEmpty),
    .dn_config_data(ctrl$config_data),
    .dn_config_en(ctrl$config_en),
    .dn_config_rdy(ctrl$config_rdy),
    .mn_config_data(ctrl$ms_config_data),
    .mn_config_numSwitches(32'd8), // Assuming 8 mult switches
    .mn_config_en(ctrl$ms_config_en),
    .mn_config_rdy(ctrl$ms_config_rdy),
    .rn_config_data(ctrl$rn_config_data),
    .rn_config_en(ctrl$rn_config_en),
    .rn_config_rdy(ctrl$rn_config_rdy),
    .input_data(ctrl$data_data),
    .input_en(ctrl$data_en),
    .input_rdy(ctrl$data_rdy),
    .output_data(output_data),
    .output_en(output_en | ctrl_art_output_en),
    .output_rdy(output_rdy)
  );

  // Result Memory C
  wire mem_c_wen;
  wire [B_ADDR_W-1:0] mem_c_waddr;
  wire [DATA_W-1:0] mem_c_wdata;
  wire ctrl_art_output_en;

  simple_mem_dp #(
    .DATA_W(DATA_W),
    .ADDR_W(B_ADDR_W)
  ) mem_C (
    .clk(CLK),
    .ren(1'b0), // Read only by TB or future units
    .raddr(0),
    .rdata(),
    .wen(mem_c_wen),
    .waddr(mem_c_waddr),
    .wdata(mem_c_wdata)
  );

endmodule
