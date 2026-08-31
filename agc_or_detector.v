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
    wire [7:0] or_async = {adc7_or, adc6_or, adc5_or, adc4_or,
                           adc3_or, adc2_or, adc1_or, adc0_or};
    wire [7:0] or_sync;
    reg  [7:0] or_stage1_reg;

    sync_nff #(.WIDTH(8)) u_sync_or (
        .dst_clk   (clk),
        .dst_rst_n (rst_n),
        .async_in  (or_async),
        .sync_out  (or_sync)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            or_stage1_reg <= 8'd0;
        end else begin
            or_stage1_reg <= or_sync;
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
        else if (axi_clear_status)
            or_status_bus_sticky1 <= or_stage1_reg;
        else
            or_status_bus_sticky1 <= or_status_bus_sticky1 | or_stage1_reg;
    end
   assign or_status_bus_sticky = or_status_bus_sticky1;
endmodule
