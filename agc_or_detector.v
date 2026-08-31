`timescale 1ns / 1ps

module agc_or_detector (
    input  wire        clk,               // 与中心 FSM 同源的工作时钟
    input  wire        rst_n,             // 异步复位，低有效

    // 1. 来自 RF-ADC IP 的 8 个实时过载报警信号 (Over Range)
    input  wire        adc0_or,
    input  wire        adc1_or,
    input  wire        adc2_or,
    input  wire        adc3_or,
    input  wire        adc4_or,
    input  wire        adc5_or,
    input  wire        adc6_or,
    input  wire        adc7_or,

    // 2. 来自 AXI-Lite 接口的清除脉冲
    input  wire        axi_clear_status,  

    // 3. 输出给中心 DSA FSM 的全局削顶告警 (触发 FAST_ATTACK)
    output reg         global_or_alert,

    // 4. 输出给 AXI-Lite 寄存器的粘性状态总线 (用于死机后的故障溯源)
    output wire  [7:0]  or_status_bus_sticky
);

    // =======================================================
    // Stage 1: 输入缓冲隔离 (斩断来自 IP 核的布线延迟)
    // =======================================================
    reg [7:0] or_stage1_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            or_stage1_reg <= 8'd0;
        end else begin
            or_stage1_reg[0] <= adc0_or;
            or_stage1_reg[1] <= adc1_or;
            or_stage1_reg[2] <= adc2_or;
            or_stage1_reg[3] <= adc3_or;
            or_stage1_reg[4] <= adc4_or;
            or_stage1_reg[5] <= adc5_or;
            or_stage1_reg[6] <= adc6_or;
            or_stage1_reg[7] <= adc7_or;
        end
    end

    // =======================================================
    // Stage 2 & 3: 硬件实时全局告警 (Pipeline OR Tree)
    // =======================================================
    reg groupA_or; 
    reg groupB_or; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            groupA_or <= 1'b0;
            groupB_or <= 1'b0;
            global_or_alert <= 1'b0;
        end else begin
            // 分组聚合
            groupA_or <= or_stage1_reg[0] | or_stage1_reg[1] | or_stage1_reg[2] | or_stage1_reg[3];
            groupB_or <= or_stage1_reg[4] | or_stage1_reg[5] | or_stage1_reg[6] | or_stage1_reg[7];
            
            // 只要有任何一根线报削顶，立刻拉高全局中断
            global_or_alert <= groupA_or | groupB_or;
        end
    end

    // =======================================================
    // Stage 4: 软件友好的粘性状态总线逻辑 (Sticky Logic)
    // =======================================================
    reg [7:0]  or_status_bus_sticky1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            or_status_bus_sticky1 <= 8'd0;
        end 
        else if (axi_clear_status) begin
            or_status_bus_sticky1 <= 8'd0; // 收到软件清除指令，清零故障码
        end 
        else begin
            // 永远锁存削顶状态，供 ARM 读取评估数据有效性
            or_status_bus_sticky1 <= or_status_bus_sticky1 | or_stage1_reg;
        end
    end
   assign or_status_bus_sticky = or_status_bus_sticky1;
endmodule