`timescale 1ns / 1ps

// =======================================================
// agc_dsa_code_converter
// -------------------------------------------------------
// 功能：将 agc_central_fsm 内部"直觉式"衰减量(dB)转换为
//       RFDC IP 实时 DSA 控制端口真正需要的 dsa_code 寄存器值。
//
// FSM 侧语义（不变，保持直觉）：
//   atten_db_in = 0            → 最小衰减 (0 dB，满增益)
//   atten_db_in = DSA_RANGE_DB → 最大衰减 (器件最大衰减值，保护态)
//
// 硬件寄存器语义（依据 DS926）：
//   DSA(dB) = RANGE - dsa_code * STEP
//   => dsa_code = (RANGE - DSA(dB)) / STEP
//
// 因此：
//   atten_db_in = 0            → hw_dsa_code = RANGE/STEP (硬件码最大)
//   atten_db_in = DSA_RANGE_DB → hw_dsa_code = 0           (硬件码最小)
//   两者方向正好相反，这正是本模块存在的意义。
//
// 实例化位置：agc_dsa_dispatcher 输出 和 RFDC IP 实时DSA端口 之间。
// 8通道统一衰减场景下，可共用一个转换实例广播给各通道；
// 若未来需要支持每通道独立码值，可为每通道各实例化一份。
// =======================================================
module agc_dsa_code_converter #(
    parameter integer DSA_RANGE_DB = 27,  // 器件DSA总衰减范围(dB)，来自RFDC IP实际配置/DS926
    parameter integer DSA_STEP_DB  = 1,   // 每个code对应的dB step，来自RFDC IP实际配置/DS926
    parameter integer CODE_WIDTH   = 5    // dsa_code位宽，需能容纳 DSA_RANGE_DB/DSA_STEP_DB
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // 来自 agc_central_fsm(经dispatcher) 的直觉式衰减量
    input  wire [CODE_WIDTH-1:0] atten_db_in,
    input  wire                  atten_db_valid,   // 对应 global_dsa_update，单拍脉冲

    // 送给 RFDC IP 实时DSA控制端口的真实寄存器码值
    output reg  [CODE_WIDTH-1:0] hw_dsa_code,
    output reg                   hw_dsa_code_valid
);

    // atten_dB=0 时对应的硬件码（硬件码域里的"最大值"，代表0dB/满增益）
    localparam [CODE_WIDTH-1:0] CODE_AT_ZERO_ATTEN =
        (DSA_RANGE_DB / DSA_STEP_DB);

    // 防御性钳位：理论上FSM侧已把 atten_db_in 限制在 [0, DSA_RANGE_DB]
    // 之内，这里兜底一次，防止意外复位态/毛刺送出非法码值
    wire [CODE_WIDTH-1:0] atten_db_clamped =
        (atten_db_in > DSA_RANGE_DB[CODE_WIDTH-1:0])
            ? DSA_RANGE_DB[CODE_WIDTH-1:0]
            : atten_db_in;

    // 核心换算：hw_dsa_code = (RANGE - atten_dB) / STEP
    // DSA_STEP_DB 是编译期常量参数，Vivado综合时会把这个除法
    // 优化成对应的常数移位/相减网络，不会生成运行时除法器；
    // 当 DSA_STEP_DB=1（多数RFSoC典型配置）时，该式退化为
    // 一次纯减法，资源开销可以忽略
    wire [CODE_WIDTH-1:0] hw_dsa_code_comb =
        (DSA_RANGE_DB[CODE_WIDTH-1:0] - atten_db_clamped) / DSA_STEP_DB[CODE_WIDTH-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时必须和 agc_central_fsm 的
            // "global_dsa_code <= DSA_MAX_VAL(最大衰减)"保命默认值对齐：
            // 最大衰减(dB)=DSA_RANGE_DB 换算成硬件码就是 0，
            // 而不是 CODE_AT_ZERO_ATTEN —— 这里如果写反，
            // 会导致上电瞬间FSM以为已保护到位，硬件却是满增益
            hw_dsa_code       <= {CODE_WIDTH{1'b0}};
            hw_dsa_code_valid <= 1'b0;
        end else begin
            hw_dsa_code_valid <= 1'b0;  // 默认拉低，保持单拍脉冲语义
            if (atten_db_valid) begin
                hw_dsa_code       <= hw_dsa_code_comb;
                hw_dsa_code_valid <= 1'b1;
            end
        end
    end

endmodule