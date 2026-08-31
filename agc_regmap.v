`timescale 1 ns / 1 ps

module agc_regmap #(
    parameter ADDRESS_WIDTH = 14,
    parameter CODE_WIDTH    = 5
) (
    // =======================================================
    // 1. 基础时钟与复位 (AXI 时钟域)
    // =======================================================
    input  wire                     up_clk,
    input  wire                     up_rstn,

    // =======================================================
    // 2. 内部精简总线 (UP Bus) - 写接口
    // =======================================================
    input  wire                     up_wreq,
    input  wire [ADDRESS_WIDTH-1:0] up_waddr, // 字地址 (Word Aligned)
    input  wire [31:0]              up_wdata,
    output reg                      up_wack,

    // =======================================================
    // 3. 内部精简总线 (UP Bus) - 读接口
    // =======================================================
    input  wire                     up_rreq,
    input  wire [ADDRESS_WIDTH-1:0] up_raddr, // 字地址 (Word Aligned)
    output reg  [31:0]              up_rdata,
    output reg                      up_rack,

    // =======================================================
    // 4. 与 top_agc 交互的业务信号
    // =======================================================
    // 输出：单周期清除脉冲 (完美替代原来的 edge_detector)
    output reg                      axi_clear_ov,
    output reg                      axi_clear_or,
    output reg                      axi_clear_th1,
    output reg                      axi_clear_th2,

    // ARM freeze control and AGC status readback.
    output reg                      agc_freeze_req,
    input  wire                     agc_freeze_active,
    input  wire [CODE_WIDTH-1:0]    current_atten_db,
    input  wire [CODE_WIDTH-1:0]    current_hw_dsa_code,
    input  wire [3:0]               current_fsm_state,
    
    // 输入：需要被 CPU 读取的粘性状态
    input  wire [7:0]               ov_status_bus_sticky,
    input  wire [7:0]               or_status_bus_sticky,
    input  wire [7:0]               th1_status_bus_sticky,
    input  wire [7:0]               th2_status_bus_sticky,
    
    // 预留的通用配置寄存器 (替代原 slv_reg2 和 slv_reg3)
    output reg  [31:0]              agc_config_1,
    output reg  [31:0]              agc_config_2
);

    // 内部暂存寄存器，用于 AXI 链路测试
    reg [31:0] up_scratch = 32'd0;

    localparam [ADDRESS_WIDTH-1:0] ADDR_COMMAND = 0;
    localparam [ADDRESS_WIDTH-1:0] ADDR_ALARMS  = 1;
    localparam [ADDRESS_WIDTH-1:0] ADDR_CONFIG1 = 2;
    localparam [ADDRESS_WIDTH-1:0] ADDR_CONFIG2 = 3;
    localparam [ADDRESS_WIDTH-1:0] ADDR_SCRATCH = 4;
    localparam [ADDRESS_WIDTH-1:0] ADDR_CONTROL = 5;
    localparam [ADDRESS_WIDTH-1:0] ADDR_STATUS  = 6;

    // =======================================================
    // WRITE LOGIC (写逻辑与脉冲生成)
    // =======================================================
    always @(posedge up_clk) begin
        if (up_rstn == 1'b0) begin
            up_wack       <= 1'b0;
            
            // 业务寄存器复位
            axi_clear_ov  <= 1'b0;
            axi_clear_or  <= 1'b0;
            axi_clear_th1 <= 1'b0;
            axi_clear_th2 <= 1'b0;
            agc_freeze_req <= 1'b0;
            agc_config_1  <= 32'd0;
            agc_config_2  <= 32'd0;
            up_scratch    <= 32'd0;
        end else begin
            // 默认情况下，立刻应答 AXI 的写请求
            up_wack <= up_wreq;
            
            // 【ADI 核心技巧：自清零脉冲 (Self-Clearing Pulse)】
            // 默认每一拍都将脉冲拉低，只有在 up_wreq 有效的那"唯一一个时钟周期"才会被拉高。
            // 这样直接省去了 edge_detector，不仅节省逻辑，时序也更好。
            axi_clear_ov  <= 1'b0;
            axi_clear_or  <= 1'b0;
            axi_clear_th1 <= 1'b0;
            axi_clear_th2 <= 1'b0;

            if (up_wreq == 1'b1) begin
                case (up_waddr)
                    // 字地址 0 (对应 AXI 字节地址 0x00)：写 1 触发对应的清除脉冲
                    ADDR_COMMAND: begin
                        axi_clear_ov  <= up_wdata[0];
                        axi_clear_or  <= up_wdata[1];
                        axi_clear_th1 <= up_wdata[2];
                        axi_clear_th2 <= up_wdata[3];
                    end
                    // 字地址 2 (对应 AXI 字节地址 0x08)：替代原 slv_reg2
                    ADDR_CONFIG1: agc_config_1 <= up_wdata;
                    // 字地址 3 (对应 AXI 字节地址 0x0C)：替代原 slv_reg3
                    ADDR_CONFIG2: agc_config_2 <= up_wdata;
                    // 字地址 4 (对应 AXI 字节地址 0x10)：暂存器，用于软件测试总线
                    ADDR_SCRATCH: up_scratch   <= up_wdata;
                    // Byte address 0x14, bit 0: 1=freeze, 0=automatic AGC.
                    ADDR_CONTROL: agc_freeze_req <= up_wdata[0];
                endcase
            end
        end
    end

    // =======================================================
    // READ LOGIC (读逻辑与地址译码)
    // =======================================================
    always @(posedge up_clk) begin
        if (up_rstn == 1'b0) begin
            up_rack  <= 1'b0;
            up_rdata <= 32'd0;
        end else begin
            // 默认情况下，立刻应答 AXI 的读请求
            up_rack <= up_rreq;
            
            if (up_rreq == 1'b1) begin
                case (up_raddr)
                    // 字地址 0 (0x00)：脉冲寄存器，读回恒为 0
                    ADDR_COMMAND: up_rdata <= 32'd0;
                    
                    // 字地址 1 (0x04)：读取 AGC 的 4 个粘性报警状态 (替代原 slv_reg1)
                    ADDR_ALARMS: up_rdata <= {th2_status_bus_sticky, th1_status_bus_sticky,
                                           or_status_bus_sticky,  ov_status_bus_sticky};
                    
                    // 字地址 2 (0x08)：回读配置 1
                    ADDR_CONFIG1: up_rdata <= agc_config_1;
                    
                    // 字地址 3 (0x0C)：回读配置 2
                    ADDR_CONFIG2: up_rdata <= agc_config_2;
                    
                    // 字地址 4 (0x10)：回读暂存器
                    ADDR_SCRATCH: up_rdata <= up_scratch;

                    ADDR_CONTROL: up_rdata <= {31'd0, agc_freeze_req};

                    // 0x18: [0] active, [1] requested, [6:2] attenuation,
                    // [11:7] RFDC code, [15:12] FSM state (for CODE_WIDTH=5).
                    ADDR_STATUS: up_rdata <= {
                        {(32-(6+2*CODE_WIDTH)){1'b0}},
                        current_fsm_state,
                        current_hw_dsa_code,
                        current_atten_db,
                        agc_freeze_req,
                        agc_freeze_active
                    };
                    
                    // 访问未映射地址时，返回 ADI 经典的 Debug 标识码
                    default:  up_rdata <= 32'hDEADBEEF; 
                endcase
            end
        end
    end

endmodule
