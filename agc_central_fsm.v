`timescale 1ns / 1ps

module agc_central_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // =======================================================
    // 1. 报警输入 (来自四大探测器)
    // =======================================================
    input  wire        global_ov_alert,   // 物理过压 (最高级)
    input  wire        global_or_alert,   // 数字削顶
    input  wire        global_th1_alert,  // 逼近上限
    input  wire        global_th2_weak,   // 全员过弱

    // =======================================================
    // 2. 指令输出 (送给后端分发器)
    // =======================================================
    output reg  [4:0]  global_dsa_code,   // 送给 agc_dsa_dispatcher
    output reg         global_dsa_update, // 送给 agc_dsa_dispatcher
    output reg         global_clear_ov,   // 送给 agc_clear_distributor
    output reg         global_clear_or    // 送给 agc_clear_distributor
);

    // =======================================================
    // 参数定义
    // =======================================================
    localparam [4:0] DSA_MAX_VAL = 5'd27; // 最大安全衰减值
    localparam [4:0] DSA_MIN_VAL = 5'd0;  // 最小衰减值
    
    localparam [4:0] STEP_FAST   = 5'd5;  // 削顶急救步进 (+5dB)
    localparam [4:0] STEP_SLOW   = 5'd1;  // 常规调理步进 (+/-1dB)

    // 死区时间配置 (请根据实际时钟频率微调，这里假设系统时钟为100MHz-300MHz)
    localparam [19:0] WAIT_OV_SETTLE = 20'd20;     // OV解锁前，等待模拟电路切换的时间
    localparam [19:0] DEAD_TIME_OV   = 20'd100000; // OV发生后的漫长冷却 (极其保守)
    localparam [19:0] DEAD_TIME_OR   = 20'd500;    // OR削顶后的中等冷却
    localparam [19:0] DEAD_TIME_TH1  = 20'd200;    // TH1常规降增益后的短冷却
    localparam [19:0] DEAD_TIME_TH2  = 20'd5000;   // TH2恢复灵敏度后的长冷却 (快降慢升法则)

    // 状态编码
    localparam [3:0] S_IDLE           = 4'd0,
                     S_OV_SET_DSA     = 4'd1,
                     S_OV_WAIT_SETTLE = 4'd2,
                     S_OV_CLEAR_LOCK  = 4'd3,
                     S_DEAD_TIME      = 4'd15;

    // 内部寄存器
    reg [3:0]  state;
    reg [19:0] delay_cnt;
    reg [19:0] current_dead_time;

    // =======================================================
    // 核心状态机逻辑
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            delay_cnt         <= 20'd0;
            current_dead_time <= 20'd0;
            
            global_dsa_code   <= DSA_MAX_VAL; // 开机默认给最大衰减，保命第一
            global_dsa_update <= 1'b0;
            global_clear_ov   <= 1'b0;
            global_clear_or   <= 1'b0;
        end else begin
            // 脉冲信号默认拉低，确保每次触发只有 1 拍高电平
            global_dsa_update <= 1'b0;
            global_clear_ov   <= 1'b0;
            global_clear_or   <= 1'b0;

            case (state)
                // ---------------------------------------------------
                // S_IDLE: 优先级轮询与状态响应
                // ---------------------------------------------------
                S_IDLE: begin
                    delay_cnt <= 20'd0;
                    
                    // 【优先级 1】: 致命物理过压
                    if (global_ov_alert) begin
                        state <= S_OV_SET_DSA;
                    end
                    
                    // 【优先级 2】: 数据削顶急救
                    else if (global_or_alert) begin
                    
                        if (global_dsa_code <= (DSA_MAX_VAL - STEP_FAST))
                            global_dsa_code <= global_dsa_code + STEP_FAST;
                        else
                            global_dsa_code <= DSA_MAX_VAL;
                            
                        global_dsa_update <= 1'b1;         // 发送更新脉冲
                        global_clear_or   <= 1'b1;         // 发送 OR 清除脉冲
                        current_dead_time <= DEAD_TIME_OR; 
                        state             <= S_DEAD_TIME;
                    end
                    
                    // 【优先级 3】: 常规防饱和
                    else if (global_th1_alert) begin
                        if (global_dsa_code < DSA_MAX_VAL)
                          global_dsa_code <= global_dsa_code + STEP_SLOW;
                        global_dsa_update <= 1'b1;
                        current_dead_time <= DEAD_TIME_TH1;
                        state             <= S_DEAD_TIME;
                    end
                    
                    // 【优先级 4】: 全局过弱，恢复灵敏度
                    else if (global_th2_weak) begin
                        if (global_dsa_code > DSA_MIN_VAL) // 防下溢出保护
                            global_dsa_code <= global_dsa_code - STEP_SLOW;
                        
                        // 注意：即使已经是 0dB，如果不更新，就不发 update
                        if (global_dsa_code > DSA_MIN_VAL) begin
                            global_dsa_update <= 1'b1;
                            current_dead_time <= DEAD_TIME_TH2;
                            state             <= S_DEAD_TIME;
                        end
                    end
                end

                // ---------------------------------------------------
                // OV 抢救专用流程 (3步曲)
                // ---------------------------------------------------
                S_OV_SET_DSA: begin
                    global_dsa_code   <= DSA_MAX_VAL; // 满级气垫
                    global_dsa_update <= 1'b1;
                    delay_cnt         <= 20'd0;      // 加上这一行
                    state             <= S_OV_WAIT_SETTLE;
                end

                S_OV_WAIT_SETTLE: begin
                    if (delay_cnt < WAIT_OV_SETTLE) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 20'd0;
                        state     <= S_OV_CLEAR_LOCK;
                    end
                end

                S_OV_CLEAR_LOCK: begin
                    global_clear_ov   <= 1'b1;          // 发送硬件底层解锁脉冲
                    current_dead_time <= DEAD_TIME_OV;  
                    state             <= S_DEAD_TIME;
                end

                // ---------------------------------------------------
                // 通用死区冷却 (共享状态)
                // ---------------------------------------------------
                S_DEAD_TIME: begin
                    // 在此期间，强行屏蔽所有外部告警（除非发生 OV，可以加入强制打断，但这通常不需要，因为 OV 的死区已经是最大安全状态）
                    if (delay_cnt < current_dead_time) begin
                        delay_cnt <= delay_cnt + 1'b1;
                        
                        // 兜底机制：如果在死区期间又发生了最高优先级的 OV，强行打断死区去抢救
                        if (global_ov_alert) begin
                            state <= S_OV_SET_DSA;
                        end
                    end else begin
                        delay_cnt <= 20'd0;
                        state     <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule