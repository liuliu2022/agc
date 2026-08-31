`timescale 1ns / 1ps
// =======================================================
// agc_dsa_dispatcher
// -------------------------------------------------------
// 项目专属"胶水层"：
//   1. 调用 agc_dsa_code_converter，把FSM域(atten_dB)语义
//      转换成硬件域(hw_dsa_code)语义；
//   2. 调用通用库模块 fanout_dispatcher_generic，完成
//      打拍 + dont_touch克隆 + 高扇出分发；
//   3. 把打平(flatten)总线映射回项目专属的具名端口
//      (adc0_01_dsa_code 等)，供 RFDC IP 直接例化。
//
// 本文件不再包含任何打拍/克隆逻辑本身——那部分已经沉淀
// 进 fanout_dispatcher_generic（个人RTL库 fanout/ 目录），
// 这里只做"项目语义 <-> 通用库接口"的映射，方便以后
// 通用逻辑升级时，胶水层完全不用改。
//
// 设计说明（8份code : 4份update 的不对称处理）：
//   fanout_dispatcher_generic 内部是1:1配对(每份code配
//   一份update)，这里NUM_OUTPUTS=8对齐code克隆数，但
//   每个tile的01/23两份update其实同源同拍，因此仅取
//   偶数index(0,2,4,6)的update接到对外的tile级update口，
//   奇数index(1,3,5,7)的update闲置不用，属于用少量FF
//   资源换通用模块零特判的取舍。
// =======================================================

module agc_dsa_dispatcher #(
    parameter integer DSA_RANGE_DB = 27,
    parameter integer DSA_STEP_DB  = 1,
    parameter integer CODE_WIDTH   = 5
)(
    input  wire        clk,
    input  wire        rst_n,

    // =======================================================
    // 1. 来自中心 DSA FSM 的全局指令（FSM域语义：atten_dB）
    // =======================================================
    input  wire [CODE_WIDTH-1:0] global_dsa_code,
    input  wire                  global_dsa_update,

    // =======================================================
    // 2. 输出给 4 个 Tile (共 8 组接口) 的物理引脚（硬件域语义：hw_dsa_code）
    // =======================================================
    // --- Tile 0 接口 ---
    output wire [CODE_WIDTH-1:0]  adc0_01_dsa_code,
    output wire [CODE_WIDTH-1:0]  adc0_23_dsa_code,
    output wire                   adc0_dsa_update,

    // --- Tile 1 接口 ---
    output wire [CODE_WIDTH-1:0]  adc1_01_dsa_code,
    output wire [CODE_WIDTH-1:0]  adc1_23_dsa_code,
    output wire                   adc1_dsa_update,

    // --- Tile 2 接口 ---
    output wire [CODE_WIDTH-1:0]  adc2_01_dsa_code,
    output wire [CODE_WIDTH-1:0]  adc2_23_dsa_code,
    output wire                   adc2_dsa_update,

    // --- Tile 3 接口 ---
    output wire [CODE_WIDTH-1:0]  adc3_01_dsa_code,
    output wire [CODE_WIDTH-1:0]  adc3_23_dsa_code,
    output wire                   adc3_dsa_update
);

    localparam integer NUM_OUTPUTS = 8;  // 4 tiles x 2 ports

    // =======================================================
    // Stage A: FSM域(atten_dB) -> 硬件域(hw_dsa_code) 语义转换
    // 8通道统一衰减，共用一个转换实例
    // =======================================================
    wire [CODE_WIDTH-1:0] hw_dsa_code_conv;
    wire                  hw_dsa_code_conv_valid;

    agc_dsa_code_converter #(
        .DSA_RANGE_DB (DSA_RANGE_DB),
        .DSA_STEP_DB  (DSA_STEP_DB),
        .CODE_WIDTH   (CODE_WIDTH)
    ) u_dsa_code_converter (
        .clk               (clk),
        .rst_n             (rst_n),
        .atten_db_in       (global_dsa_code),
        .atten_db_valid    (global_dsa_update),
        .hw_dsa_code       (hw_dsa_code_conv),
        .hw_dsa_code_valid (hw_dsa_code_conv_valid)
    );

    // =======================================================
    // Stage B: 通用高扇出分发器（个人RTL库 fanout_dispatcher_generic）
    // 复位值 = 硬件域"最大衰减"码值 = 0，
    // 与 agc_dsa_code_converter 的复位语义保持一致
    // =======================================================
    wire [NUM_OUTPUTS*CODE_WIDTH-1:0] dsa_code_flat;
    wire [NUM_OUTPUTS-1:0]            dsa_update_flat;

    fanout_dispatcher_generic #(
        .DATA_WIDTH  (CODE_WIDTH),
        .NUM_OUTPUTS (NUM_OUTPUTS),
        .RESET_VALUE ({CODE_WIDTH{1'b0}})
    ) u_fanout_dispatcher_generic (
        .clk             (clk),
        .rst_n           (rst_n),
        .data_in         (hw_dsa_code_conv),
        .data_update     (hw_dsa_code_conv_valid),
        .data_out        (dsa_code_flat),
        .data_out_update (dsa_update_flat)
    );

    // =======================================================
    // Stage C: 打平总线 -> 项目专属具名端口映射
    // index映射关系：0=tile0_01 1=tile0_23 2=tile1_01 3=tile1_23
    //               4=tile2_01 5=tile2_23 6=tile3_01 7=tile3_23
    // =======================================================
    assign adc0_01_dsa_code = dsa_code_flat[1*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc0_23_dsa_code = dsa_code_flat[2*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc0_dsa_update  = dsa_update_flat[0]; // 与index1(23)同源同拍，取其一

    assign adc1_01_dsa_code = dsa_code_flat[3*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc1_23_dsa_code = dsa_code_flat[4*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc1_dsa_update  = dsa_update_flat[2];

    assign adc2_01_dsa_code = dsa_code_flat[5*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc2_23_dsa_code = dsa_code_flat[6*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc2_dsa_update  = dsa_update_flat[4];

    assign adc3_01_dsa_code = dsa_code_flat[7*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc3_23_dsa_code = dsa_code_flat[8*CODE_WIDTH-1 -: CODE_WIDTH];
    assign adc3_dsa_update  = dsa_update_flat[6];

endmodule