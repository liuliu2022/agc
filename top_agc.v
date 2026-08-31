`timescale 1ns / 1ps

// =======================================================
// top_agc
// -------------------------------------------------------
// 8通道 RFSoC AGC 顶层集成模块
//
// 数据流：
//   4x8探测器(OV/OR/TH1/TH2) --alert--> agc_central_fsm
//   agc_central_fsm --clear_ov/or--> agc_clear_distributor --> 8通道物理清除引脚
//   agc_central_fsm --atten_dB(直觉式)+update--> agc_dsa_dispatcher
//     （dB->硬件码转换 + 打拍 + dont_touch克隆分发，均已内建于
//       agc_dsa_dispatcher 内部，顶层不再单独例化converter）
//   agc_dsa_dispatcher --> 4 Tile 物理DSA引脚
//
// 说明：
//   1. [接口变更] agc_dsa_code_converter 已下沉到
//      agc_dsa_dispatcher 内部例化，顶层不再重复例化。
//      agc_dsa_dispatcher 的 global_dsa_code/global_dsa_update
//      输入端口语义是 FSM域(atten_dB)，而不是硬件码——
//      这与旧版top_agc的连线方式不同，务必确认没有在此
//      之外的地方再次插入转换逻辑，否则会导致dB->code
//      被转换两次，产生错误的衰减码值。
//   2. 软件友好的粘性状态总线 (Sticky Logic) 已经内建在各探测器
//      模块内部，本顶层暂不处理 AXI-Lite 地址译码，仅将
//      *_status_bus_sticky 和 axi_clear_* 作为占位端口引出，
//      后续接入 AXI-Lite 寄存器组时再对齐映射关系。
//   3. CLK_FREQ_HZ 参数化改造：agc_central_fsm 目前死区时间仍是
//      写死的 localparam，尚未开放 CLK_FREQ_HZ 参数，待 Vivado
//      确认 AXI4-Stream fabric 时钟频率后，需要回头给
//      agc_central_fsm 补上该参数并在此处透传，本文件暂不改动
//      子模块接口。
// =======================================================
module top_agc #(
    parameter integer DSA_RANGE_DB = 27,  // 器件DSA总衰减范围(dB)，需与RFDC IP实际配置(DS926)一致
    parameter integer DSA_STEP_DB  = 1,   // 每个code对应的dB step
    parameter integer CODE_WIDTH   = 5    // dsa_code位宽
)(
    input  wire        clk,
    input  wire        rst_n,

    // =======================================================
    // 1. 来自 8 路 RF-ADC IP 的实时报警信号
    // =======================================================
    input  wire        adc0_ov,  input wire adc1_ov,  input wire adc2_ov,  input wire adc3_ov,
    input  wire        adc4_ov,  input wire adc5_ov,  input wire adc6_ov,  input wire adc7_ov,

    input  wire        adc0_or,  input wire adc1_or,  input wire adc2_or,  input wire adc3_or,
    input  wire        adc4_or,  input wire adc5_or,  input wire adc6_or,  input wire adc7_or,

    input  wire        adc0_th1, input wire adc1_th1, input wire adc2_th1, input wire adc3_th1,
    input  wire        adc4_th1, input wire adc5_th1, input wire adc6_th1, input wire adc7_th1,

    input  wire        adc0_th2, input wire adc1_th2, input wire adc2_th2, input wire adc3_th2,
    input  wire        adc4_th2, input wire adc5_th2, input wire adc6_th2, input wire adc7_th2,

    // =======================================================
    // 2. 来自 AXI-Lite 的清除脉冲占位输入 (地址译码暂不处理)
    // =======================================================
    input  wire        axi_clear_ov,
    input  wire        axi_clear_or,
    input  wire        axi_clear_th1,
    input  wire        axi_clear_th2,

    // =======================================================
    // 3. 供 AXI-Lite 寄存器读取的粘性状态总线占位输出
    // =======================================================
    output wire [7:0]  ov_status_bus_sticky,
    output wire [7:0]  or_status_bus_sticky,
    output wire [7:0]  th1_status_bus_sticky,
    output wire [7:0]  th2_status_bus_sticky,

    // ARM control/status. Keep agc_freeze_req high throughout DMA.
    input  wire                  agc_freeze_req,
    output wire                  agc_freeze_active,
    output wire [CODE_WIDTH-1:0] current_atten_db,
    output wire [CODE_WIDTH-1:0] current_hw_dsa_code,
    output wire [3:0]            current_fsm_state,

    // =======================================================
    // 4. 送给 RFDC IP 的物理清除引脚 (8通道 x OV/OR)
    // =======================================================
    output wire        adc0_clear_ov, output wire adc1_clear_ov,
    output wire        adc2_clear_ov, output wire adc3_clear_ov,
    output wire        adc4_clear_ov, output wire adc5_clear_ov,
    output wire        adc6_clear_ov, output wire adc7_clear_ov,

    output wire        adc0_clear_or, output wire adc1_clear_or,
    output wire        adc2_clear_or, output wire adc3_clear_or,
    output wire        adc4_clear_or, output wire adc5_clear_or,
    output wire        adc6_clear_or, output wire adc7_clear_or,

    // =======================================================
    // 5. 送给 RFDC IP 的实时 DSA 控制端口 (4 Tile x 2组)
    // =======================================================
    output wire [CODE_WIDTH-1:0] adc0_01_dsa_code, output wire [CODE_WIDTH-1:0] adc0_23_dsa_code, output wire adc0_dsa_update,
    output wire [CODE_WIDTH-1:0] adc1_01_dsa_code, output wire [CODE_WIDTH-1:0] adc1_23_dsa_code, output wire adc1_dsa_update,
    output wire [CODE_WIDTH-1:0] adc2_01_dsa_code, output wire [CODE_WIDTH-1:0] adc2_23_dsa_code, output wire adc2_dsa_update,
    output wire [CODE_WIDTH-1:0] adc3_01_dsa_code, output wire [CODE_WIDTH-1:0] adc3_23_dsa_code, output wire adc3_dsa_update
);

    // =======================================================
    // 内部互连线
    // =======================================================
    wire        global_ov_alert;
    wire        global_or_alert;
    wire        global_th1_alert;
    wire        global_th2_weak_alert;   // th2_detector输出名，接入fsm的global_th2_weak

    wire [CODE_WIDTH-1:0] atten_db_intuitive;   // fsm侧直觉式dB衰减量，直接喂给dispatcher
    wire                   atten_db_valid;

    wire        global_clear_ov;
    wire        global_clear_or;

    // =======================================================
    // 1. 四大探测器 (OV / OR / TH1 / TH2)
    // =======================================================
    agc_ov_detector u_ov_detector (
        .clk                  (clk),
        .rst_n                (rst_n),
        .adc0_ov              (adc0_ov),
        .adc1_ov              (adc1_ov),
        .adc2_ov              (adc2_ov),
        .adc3_ov              (adc3_ov),
        .adc4_ov              (adc4_ov),
        .adc5_ov              (adc5_ov),
        .adc6_ov              (adc6_ov),
        .adc7_ov              (adc7_ov),
        .axi_clear_status     (axi_clear_ov),
        .global_ov_alert      (global_ov_alert),
        .ov_status_bus_sticky (ov_status_bus_sticky)
    );

    agc_or_detector u_or_detector (
        .clk                  (clk),
        .rst_n                (rst_n),
        .adc0_or              (adc0_or),
        .adc1_or              (adc1_or),
        .adc2_or              (adc2_or),
        .adc3_or              (adc3_or),
        .adc4_or              (adc4_or),
        .adc5_or              (adc5_or),
        .adc6_or              (adc6_or),
        .adc7_or              (adc7_or),
        .axi_clear_status     (axi_clear_or),
        .global_or_alert      (global_or_alert),
        .or_status_bus_sticky (or_status_bus_sticky)
    );

    agc_th1_detector u_th1_detector (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .adc0_th1              (adc0_th1),
        .adc1_th1              (adc1_th1),
        .adc2_th1              (adc2_th1),
        .adc3_th1              (adc3_th1),
        .adc4_th1              (adc4_th1),
        .adc5_th1              (adc5_th1),
        .adc6_th1              (adc6_th1),
        .adc7_th1              (adc7_th1),
        .axi_clear_status      (axi_clear_th1),
        .global_th1_alert      (global_th1_alert),
        .th1_status_bus_sticky (th1_status_bus_sticky)
    );

    agc_th2_detector u_th2_detector (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .adc0_th2               (adc0_th2),
        .adc1_th2               (adc1_th2),
        .adc2_th2               (adc2_th2),
        .adc3_th2               (adc3_th2),
        .adc4_th2               (adc4_th2),
        .adc5_th2               (adc5_th2),
        .adc6_th2               (adc6_th2),
        .adc7_th2               (adc7_th2),
        .axi_clear_status       (axi_clear_th2),
        .global_th2_weak_alert  (global_th2_weak_alert),
        .th2_status_bus_sticky  (th2_status_bus_sticky)
    );

    // =======================================================
    // 2. 中心 DSA 控制状态机
    //    注：global_th2_weak_alert -> global_th2_weak 仅为端口命名差异
    // =======================================================
    agc_central_fsm #(
        .CODE_WIDTH   (CODE_WIDTH),
        .DSA_RANGE_DB (DSA_RANGE_DB)
    ) u_central_fsm (
        .clk                (clk                  ),
        .rst_n              (rst_n                ),
        .global_ov_alert    (global_ov_alert      ),
        .global_or_alert    (global_or_alert      ),
        .global_th1_alert   (global_th1_alert     ),
        .global_th2_weak    (global_th2_weak_alert),
        .freeze_req         (agc_freeze_req       ),
        .freeze_active      (agc_freeze_active    ),
        .fsm_state          (current_fsm_state    ),
        .global_dsa_code    (atten_db_intuitive   ),
        .global_dsa_update  (atten_db_valid       ),
        .global_clear_ov    (global_clear_ov      ),
        .global_clear_or    (global_clear_or      )
    );

    assign current_atten_db    = atten_db_intuitive;
    assign current_hw_dsa_code = adc0_01_dsa_code;

    // =======================================================
    // 3. DSA 码值分发到 4 个 Tile
    //    [变更] dB->硬件码转换已内建于 agc_dsa_dispatcher 内部，
    //    顶层直接把FSM的atten_dB(直觉式)喂给dispatcher，
    //    不再需要顶层单独例化 agc_dsa_code_converter。
    // =======================================================
    agc_dsa_dispatcher #(
        .DSA_RANGE_DB (DSA_RANGE_DB),
        .DSA_STEP_DB  (DSA_STEP_DB),
        .CODE_WIDTH   (CODE_WIDTH)
    ) u_dsa_dispatcher (
        .clk                (clk),
        .rst_n              (rst_n),
        .global_dsa_code    (atten_db_intuitive),  // FSM域语义，非硬件码
        .global_dsa_update  (atten_db_valid),

        .adc0_01_dsa_code   (adc0_01_dsa_code),
        .adc0_23_dsa_code   (adc0_23_dsa_code),
        .adc0_dsa_update    (adc0_dsa_update),

        .adc1_01_dsa_code   (adc1_01_dsa_code),
        .adc1_23_dsa_code   (adc1_23_dsa_code),
        .adc1_dsa_update    (adc1_dsa_update),

        .adc2_01_dsa_code   (adc2_01_dsa_code),
        .adc2_23_dsa_code   (adc2_23_dsa_code),
        .adc2_dsa_update    (adc2_dsa_update),

        .adc3_01_dsa_code   (adc3_01_dsa_code),
        .adc3_23_dsa_code   (adc3_23_dsa_code),
        .adc3_dsa_update    (adc3_dsa_update)
    );

    // =======================================================
    // 4. OV/OR 清除脉冲分发到 8 个物理通道
    // =======================================================
    agc_clear_distributor u_clear_distributor (
        .clk              (clk),
        .rst_n            (rst_n),
        .global_clear_ov  (global_clear_ov),
        .global_clear_or  (global_clear_or),

        .adc0_clear_ov (adc0_clear_ov), .adc1_clear_ov (adc1_clear_ov),
        .adc2_clear_ov (adc2_clear_ov), .adc3_clear_ov (adc3_clear_ov),
        .adc4_clear_ov (adc4_clear_ov), .adc5_clear_ov (adc5_clear_ov),
        .adc6_clear_ov (adc6_clear_ov), .adc7_clear_ov (adc7_clear_ov),

        .adc0_clear_or (adc0_clear_or), .adc1_clear_or (adc1_clear_or),
        .adc2_clear_or (adc2_clear_or), .adc3_clear_or (adc3_clear_or),
        .adc4_clear_or (adc4_clear_or), .adc5_clear_or (adc5_clear_or),
        .adc6_clear_or (adc6_clear_or), .adc7_clear_or (adc7_clear_or)
    );

endmodule
