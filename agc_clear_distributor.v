`timescale 1ns / 1ps

module agc_clear_distributor (
    input  wire        clk,
    input  wire        rst_n,

    // =======================================================
    // 1. 来自中心 DSA FSM 的全局清除指令 (单拍脉冲)
    // =======================================================
    input  wire        global_clear_ov,
    input  wire        global_clear_or,

    // =======================================================
    // 2. 输出给 8 个 ADC 通道的物理清除引脚
    // =======================================================
    // Over Voltage 独立清除引脚 (8个)
    output reg         adc0_clear_ov,
    output reg         adc1_clear_ov,
    output reg         adc2_clear_ov,
    output reg         adc3_clear_ov,
    output reg         adc4_clear_ov,
    output reg         adc5_clear_ov,
    output reg         adc6_clear_ov,
    output reg         adc7_clear_ov,

    // Over Range 独立清除引脚 (8个)
    output reg         adc0_clear_or,
    output reg         adc1_clear_or,
    output reg         adc2_clear_or,
    output reg         adc3_clear_or,
    output reg         adc4_clear_or,
    output reg         adc5_clear_or,
    output reg         adc6_clear_or,
    output reg         adc7_clear_or
);

    // =======================================================
    // 脉冲克隆与扇出隔离 (Register Duplication 1 to 8)
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 异步复位时全部拉低
            adc0_clear_ov <= 1'b0; adc1_clear_ov <= 1'b0;
            adc2_clear_ov <= 1'b0; adc3_clear_ov <= 1'b0;
            adc4_clear_ov <= 1'b0; adc5_clear_ov <= 1'b0;
            adc6_clear_ov <= 1'b0; adc7_clear_ov <= 1'b0;
            
            adc0_clear_or <= 1'b0; adc1_clear_or <= 1'b0;
            adc2_clear_or <= 1'b0; adc3_clear_or <= 1'b0;
            adc4_clear_or <= 1'b0; adc5_clear_or <= 1'b0;
            adc6_clear_or <= 1'b0; adc7_clear_or <= 1'b0;
        end else begin
            // 收到 FSM 的 1 拍高电平后，在这里打 1 拍，并克隆出 8 份独立驱动
            adc0_clear_ov <= global_clear_ov; adc1_clear_ov <= global_clear_ov;
            adc2_clear_ov <= global_clear_ov; adc3_clear_ov <= global_clear_ov;
            adc4_clear_ov <= global_clear_ov; adc5_clear_ov <= global_clear_ov;
            adc6_clear_ov <= global_clear_ov; adc7_clear_ov <= global_clear_ov;
            
            adc0_clear_or <= global_clear_or; adc1_clear_or <= global_clear_or;
            adc2_clear_or <= global_clear_or; adc3_clear_or <= global_clear_or;
            adc4_clear_or <= global_clear_or; adc5_clear_or <= global_clear_or;
            adc6_clear_or <= global_clear_or; adc7_clear_or <= global_clear_or;
        end
    end

endmodule