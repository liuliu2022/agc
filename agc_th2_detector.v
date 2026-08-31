`timescale 1ns / 1ps

module agc_th2_detector (
    input  wire        clk,               // 状态机工作时钟
    input  wire        rst_n,             // 异步复位，低有效

    // 1. 来自 RF-ADC IP 的 8 个实时阈值报警信号 (Threshold 2)
    input  wire        adc0_th2,
    input  wire        adc1_th2,
    input  wire        adc2_th2,
    input  wire        adc3_th2,
    input  wire        adc4_th2,
    input  wire        adc5_th2,
    input  wire        adc6_th2,
    input  wire        adc7_th2,

    // 2. 来自 AXI-Lite 接口的清除脉冲
    input  wire        axi_clear_status,  // 高有效脉冲

    // 3. 输出给中心 DSA FSM 的全局过弱告警 (高电平代表：全员过弱，允许减小衰减)
    output reg         global_th2_weak_alert,

    // 4. 输出给 AXI-Lite 寄存器的粘性状态总线 (高电平代表：该通道曾经跃过 TH2)
    output wire  [7:0]  th2_status_bus_sticky
);

    // =======================================================
    // Stage 0: CDC - clk_adcX 域 -> clk (s_axi_aclk) 域
    // 8 路独立报警位，用向量化 2FF 同步器一次性处理
    // =======================================================
    wire [7:0] th2_async;
    wire [7:0] th2_sync;

    assign th2_async = {adc7_th2, adc6_th2, adc5_th2, adc4_th2,
                        adc3_th2, adc2_th2, adc1_th2, adc0_th2};
                                          
        sync_nff #(
        .WIDTH       (8   )
    ) u_sync_th2 (
        .dst_clk    (clk      ),
        .dst_rst_n  (rst_n    ),
        .async_in   (th2_async),
        .sync_out   (th2_sync )
    );                    
                        
                                     
    // =======================================================
    // Stage 1: 输入缓冲隔离
    // =======================================================
    reg [7:0] th2_stage1_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            th2_stage1_reg <= 8'd0;
        end else begin
            th2_stage1_reg <= th2_sync;
        end
    end

    // =======================================================
    // Stage 2: 分组聚合 (Partial OR)
    // 注意：这里仍然是 OR，我们在下一级再做取反
    // =======================================================
    reg groupA_over_th2; 
    reg groupB_over_th2; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            groupA_over_th2 <= 1'b0;
            groupB_over_th2 <= 1'b0;
        end else begin
            groupA_over_th2 <= th2_stage1_reg[0] | th2_stage1_reg[1] | th2_stage1_reg[2] | th2_stage1_reg[3];
            groupB_over_th2 <= th2_stage1_reg[4] | th2_stage1_reg[5] | th2_stage1_reg[6] | th2_stage1_reg[7];
        end
    end

    // =======================================================
    // Stage 3: 硬件实时全局告警 (NOR Logic)
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_th2_weak_alert <= 1'b0; // 复位时默认不触发减小增益动作
        end else begin
            // 核心逻辑：NOR (或非)。
            // 只有当 groupA 和 groupB 都是 0 时 (即8个通道全都是0)，才输出 1。
            global_th2_weak_alert <= ~(groupA_over_th2 | groupB_over_th2);
        end
    end

    // =======================================================
    // Stage 4: 软件友好的粘性状态总线逻辑 
    // =======================================================
     reg  [7:0]  th2_status_bus_sticky1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            th2_status_bus_sticky1 <= 8'd0;
        end 
        else if (axi_clear_status) begin
            th2_status_bus_sticky1 <= 8'd0;
        end 
        else begin
            // 只要出现过高电平（越过TH2），就锁存为 1
            th2_status_bus_sticky1 <= th2_status_bus_sticky1 | th2_stage1_reg;
        end
    end
    assign th2_status_bus_sticky = th2_status_bus_sticky1;
endmodule