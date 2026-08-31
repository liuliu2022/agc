`timescale 1ns / 1ps
module agc_th1_detector (
    input  wire        clk,               // 状态机工作时钟 (s_axi_aclk, 200MHz)
    input  wire        rst_n,             // 异步复位，低有效，s_axi_aclk域同步释放

    // 1. 来自 RF-ADC IP 的 8 个实时阈值报警信号 (clk_adcX 域，未同步)
    input  wire        adc0_th1,
    input  wire        adc1_th1,
    input  wire        adc2_th1,
    input  wire        adc3_th1,
    input  wire        adc4_th1,
    input  wire        adc5_th1,
    input  wire        adc6_th1,
    input  wire        adc7_th1,

    // 2. 来自 AXI-Lite 接口的清除脉冲 (ARM 写寄存器触发, clk 域原生信号)
    input  wire        axi_clear_status,

    // 3. 输出给中心 DSA FSM 的全局报警 (纯实时，无粘性，供底层快速响应)
    output reg         global_th1_alert,

    // 4. 输出给 AXI-Lite 寄存器的粘性状态总线 (供 ARM 慢慢读)
    output wire  [7:0]  th1_status_bus_sticky
);

    // =======================================================
    // Stage 0: CDC - clk_adcX 域 -> clk (s_axi_aclk) 域
    // 8 路独立报警位，用向量化 2FF 同步器一次性处理
    // =======================================================
    wire [7:0] th1_async;
    wire [7:0] th1_sync;

    assign th1_async = {adc7_th1, adc6_th1, adc5_th1, adc4_th1,
                        adc3_th1, adc2_th1, adc1_th1, adc0_th1};

    sync_nff #(
        .WIDTH       (8   )
    ) u_sync_th1 (
        .dst_clk    (clk      ),
        .dst_rst_n  (rst_n    ),
        .async_in   (th1_async),
        .sync_out   (th1_sync )
    );

    // =======================================================
    // Stage 1: 流水线缓冲对齐 (基于已同步的信号)
    // 说明：th1_sync 本身已经是 clk 域内干净、寄存器输出的信号
    //       (sync_2ff 内部的 sync_ff 就是这一级寄存器)。
    //       这保留一级独立缓冲，是为了让 OR-tree 流水线的
    //       深度与你原设计保持一致，便于后级时序收敛；
    //       如果不在意这一级延迟，也可以直接用 th1_sync 接入
    //       Stage 2，省掉这一级寄存器。
    // =======================================================
    reg [7:0] th1_stage1_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            th1_stage1_reg <= 8'd0;
        end else begin
            th1_stage1_reg <= th1_sync;
        end
    end

    // =======================================================
    // Stage 2 & 3: 硬件实时全局报警 (Pipeline OR Tree)
    // =======================================================
    reg groupA_alert;
    reg groupB_alert;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            groupA_alert     <= 1'b0;
            groupB_alert     <= 1'b0;
            global_th1_alert <= 1'b0;
        end else begin
            // 分组 OR
            groupA_alert <= th1_stage1_reg[0] | th1_stage1_reg[1] | th1_stage1_reg[2] | th1_stage1_reg[3];
            groupB_alert <= th1_stage1_reg[4] | th1_stage1_reg[5] | th1_stage1_reg[6] | th1_stage1_reg[7];

            // 全局 OR，直接送给 PL 端的 DSA 中心状态机 (无需等待软件干预)
            global_th1_alert <= groupA_alert | groupB_alert;
        end
    end

    // =======================================================
    // Stage 4: 软件友好的粘性状态总线逻辑 (Sticky Logic)
    // =======================================================
    reg [7:0]  th1_status_bus_sticky1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            th1_status_bus_sticky1 <= 8'd0;
        end
        else if (axi_clear_status)
            th1_status_bus_sticky1 <= th1_stage1_reg;
        else
            th1_status_bus_sticky1 <= th1_status_bus_sticky1 | th1_stage1_reg;
    end
     assign th1_status_bus_sticky = th1_status_bus_sticky1;
endmodule
