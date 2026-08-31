`timescale 1ns / 1ps

module agc_ov_detector (
    input  wire        clk,               // 与中心 FSM 同源的工作时钟
    input  wire        rst_n,             // 异步复位，低有效

    // 1. 来自 RF-ADC IP 的 8 个实时过压报警信号 (对应你的物理接口)
    input  wire        adc0_ov,
    input  wire        adc1_ov,
    input  wire        adc2_ov,
    input  wire        adc3_ov,
    input  wire        adc4_ov,
    input  wire        adc5_ov,
    input  wire        adc6_ov,
    input  wire        adc7_ov,

    // 2. 来自 AXI-Lite 接口的清除脉冲
    input  wire        axi_clear_status,  

    // 3. 输出给中心 DSA FSM 的全局致命告警 (最高优先级中断)
    output reg         global_ov_alert,

    // 4. 输出给 AXI-Lite 寄存器的粘性状态总线 (用于死机后的故障溯源)
    output wire  [7:0]  ov_status_bus_sticky
);

    // =======================================================
    // Stage 1: 输入缓冲隔离 (斩断来自 IP 核的布线延迟)
    // =======================================================
    reg [7:0] ov_stage1_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ov_stage1_reg <= 8'd0;
        end else begin
            ov_stage1_reg[0] <= adc0_ov;
            ov_stage1_reg[1] <= adc1_ov;
            ov_stage1_reg[2] <= adc2_ov;
            ov_stage1_reg[3] <= adc3_ov;
            ov_stage1_reg[4] <= adc4_ov;
            ov_stage1_reg[5] <= adc5_ov;
            ov_stage1_reg[6] <= adc6_ov;
            ov_stage1_reg[7] <= adc7_ov;
        end
    end

    // =======================================================
    // Stage 2 & 3: 硬件实时全局告警 (Pipeline OR Tree)
    // =======================================================
    reg groupA_ov; 
    reg groupB_ov; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            groupA_ov <= 1'b0;
            groupB_ov <= 1'b0;
            global_ov_alert <= 1'b0;
        end else begin
            // 分组聚合
            groupA_ov <= ov_stage1_reg[0] | ov_stage1_reg[1] | ov_stage1_reg[2] | ov_stage1_reg[3];
            groupB_ov <= ov_stage1_reg[4] | ov_stage1_reg[5] | ov_stage1_reg[6] | ov_stage1_reg[7];
            
            // 只要有任何一根线报过压，立刻拉高全局中断
            global_ov_alert <= groupA_ov | groupB_ov;
        end
    end

    // =======================================================
    // Stage 4: 软件友好的粘性状态总线逻辑 (Sticky Logic)
    // =======================================================
    reg  [7:0]  ov_status_bus_sticky1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ov_status_bus_sticky1 <= 8'd0;
        end 
        else if (axi_clear_status) begin
            ov_status_bus_sticky1 <= 8'd0; // 收到软件清除指令，清零故障码
        end 
        else begin
            // 永远锁存最高危的过压状态
            ov_status_bus_sticky1 <= ov_status_bus_sticky1 | ov_stage1_reg;
        end
    end
   assign ov_status_bus_sticky = ov_status_bus_sticky1;
endmodule