# RFSoC AGC RTL

本目录实现一套面向 `xczu47dr-ffve1156-2-i` RFSoC 的 8 路 ADC 全局自动增益控制。它根据 RFDC 的 OV、OR、TH1、TH2 状态统一调整 DSA，在采集前可由 ARM 冻结当前 DSA，使一次 DMA 搬运期间所有样本保持相同的模拟增益。

这套设计采用“8 路报警、1 个全局衰减值、广播到 4 个 ADC Tile/8 个 DSA 端口”的策略，不是逐通道独立 AGC。

## 1. 系统结构

```text
RFDC OV/OR/TH1/TH2 (8 channels)
                 |
                 v
      detector + CDC + sticky status
                 |
                 v
          agc_central_fsm
          |              |
          |              +--> OV/OR clear distributor --> RFDC clear ports
          v
 intuitive attenuation (dB)
          |
          v
   dB-to-hardware-code converter
          |
          v
 registered fanout --> 4 Tiles / 8 DSA code ports

ARM AXI-Lite --> up_axi --> agc_regmap --> freeze request/status readback
```

推荐直接实例化 `top_agc_axi.v`。该模块把 AXI-Lite、寄存器映射、AGC 核和 RFDC 控制端口组合在同一个 `s_axi_aclk` 时钟域内。

## 2. 文件说明

| 文件 | 作用 |
|---|---|
| `top_agc_axi.v` | 推荐使用的完整 AXI-Lite 外设顶层 |
| `top_agc.v` | 不带 AXI 总线的 AGC 核心顶层 |
| `agc_central_fsm.v` | 全局 AGC 优先级、步进、死区和冻结状态控制 |
| `agc_ov_detector.v` | 8 路过压同步、聚合和粘滞记录 |
| `agc_or_detector.v` | 8 路削顶/超量程同步、聚合和粘滞记录 |
| `agc_th1_detector.v` | TH1 同步、聚合和粘滞记录 |
| `agc_th2_detector.v` | TH2 同步、全通道过弱判断和启动有效期保护 |
| `agc_dsa_code_converter.v` | 直观衰减 dB 到 RFDC 硬件 DSA 码转换 |
| `agc_dsa_dispatcher.v` | DSA 转换器和广播模块的项目接口封装 |
| `fanout_dispatcher_generic.v` | 带寄存器复制的高扇出数据/更新脉冲广播 |
| `agc_clear_distributor.v` | 将 OV/OR 清除脉冲复制到 8 路通道 |
| `sync_2ff.v` | 独立单比特状态信号的多级 CDC 同步器 |
| `agc_regmap.v` | ARM 可访问的控制、状态和报警寄存器 |
| `up_axi.v` | ADI 风格 AXI-Lite 到简化 UP 总线桥接器 |
| `agc_regs.h` | ARM 软件公开类型、宏和函数声明 |
| `agc_regs.c` | ARM MMIO、冻结、解冻、状态解析实现 |
| `AGC_ARM_INTERFACE.md` | 精简版 ARM 寄存器及接线说明 |

## 3. DSA 数值语义

FSM 内部的 `current_atten_db` 使用直观衰减量：

- `0` 表示 0 dB 衰减，即最高增益。
- `27` 表示 27 dB 衰减，即默认安全低增益状态。

RFDC 硬件码采用相反方向：

```text
hardware_dsa_code = (DSA_RANGE_DB - attenuation_db) / DSA_STEP_DB
```

默认参数下：

| 衰减量 | RFDC 硬件码 |
|---:|---:|
| 27 dB | 0 |
| 26 dB | 1 |
| 5 dB | 22 |
| 0 dB | 27 |

上电解除复位后，FSM 会主动发送一次 `27 dB/code 0` 更新脉冲，不能只依赖数据总线的复位值。

## 4. AGC 控制策略

`agc_central_fsm` 的优先级从高到低为：

1. OV：立即切换到最大衰减 27 dB。
2. OR：快速增加 5 dB 衰减。
3. TH1：每次增加 1 dB 衰减。
4. 全部通道低于 TH2：每次减少 1 dB 衰减，提高增益。

所有加减均带上下限饱和保护，不允许超过 `0..DSA_RANGE_DB`。每次调整后进入相应死区，避免阈值附近来回振荡。死区默认值位于 `agc_central_fsm.v` 的参数列表中，单位是 `clk` 周期。

TH2 在复位释放后的前几个周期被屏蔽，直到同步器和 OR 树中的输入有效，避免上电时把同步寄存器的复位 0 误判为“全通道过弱”。

## 5. ARM 寄存器

偏移量相对于 Vivado Address Editor 分配的 AXI-Lite 基地址。

| 偏移 | 名称 | 访问 | 内容 |
|---:|---|---|---|
| `0x00` | COMMAND | WO | bit 0/1/2/3 清除 OV/OR/TH1/TH2 粘滞状态 |
| `0x04` | ALARMS | RO | `[7:0]` OV、`[15:8]` OR、`[23:16]` TH1、`[31:24]` TH2 |
| `0x08` | CONFIG1 | RW | 预留，当前不参与 AGC |
| `0x0c` | CONFIG2 | RW | 预留，当前不参与 AGC |
| `0x10` | SCRATCH | RW | AXI 总线读写测试寄存器 |
| `0x14` | CONTROL | RW | bit 0：DSA 冻结请求 |
| `0x18` | STATUS | RO | 冻结确认、当前衰减、硬件码和 FSM 状态 |

默认 `CODE_WIDTH=5` 时，`STATUS` 定义为：

| 位 | 含义 |
|---:|---|
| 0 | `freeze_active`，硬件已完成冻结 |
| 1 | `freeze_requested`，ARM 控制寄存器当前值 |
| 6:2 | 当前直观衰减 dB |
| 11:7 | 当前 RFDC 硬件 DSA 码 |
| 15:12 | FSM 状态 |

ARM 必须等待 `freeze_active=1`，不能只根据写入 `freeze_requested=1` 就立即启动 DMA。

## 6. DMA 冻结机制

冻结请求是持续电平，不是单周期命令：

1. 清除旧报警。
2. ARM 向 `CONTROL` 写 1。
3. FSM 立即停止产生新的 DSA 更新。
4. 硬件等待 4 个 PL 时钟，让已经进入 FSM、转换器和广播寄存器的更新到达 RFDC 端口。
5. `STATUS.freeze_active` 置 1。
6. ARM 读取锁定后的 DSA 值，然后启动 DMA。
7. DMA 完成后读取 `ALARMS`，判断本帧是否发生过 OV/OR。
8. ARM 向 `CONTROL` 写 0，AGC 在保护延迟后恢复自动调整。

冻结期间报警检测和粘滞记录仍然工作，但报警不会改变 DSA。这保证增益一致，却不能保证输入幅度变化后永不饱和。因此软件应丢弃冻结期间出现 OV/OR 的数据帧，或者在系统需求允许时设计“OV 强制中止 DMA”的上层策略。

## 7. ARM 软件使用

将 `agc_regs.c` 和 `agc_regs.h` 加入 Vitis standalone 工程，或加入 Linux 用户态/驱动工程。传入的 `base` 必须是：

- bare-metal：Vivado/Vitis 导出的 AGC AXI 物理基地址；
- Linux 用户态：通过 `/dev/mem` 或 UIO `mmap()` 后得到的虚拟地址；
- Linux 内核：经过 `ioremap()` 的地址需要使用内核 `readl/writel` 封装，不能直接照搬当前用户态 MMIO 实现。

最小调用示例：

```c
#include "agc_regs.h"

int capture_one_frame(uintptr_t agc_base)
{
    agc_status_t locked;
    agc_alarms_t alarms;

    agc_clear_alarms(agc_base, AGC_COMMAND_CLEAR_ALL);

    if (agc_freeze_for_dma(agc_base, 100000u, &locked) != 0)
        return -1;

    /* dma_start(); */
    /* dma_wait_complete(); */

    alarms = agc_read_alarms(agc_base);
    agc_release_after_dma(agc_base);

    if ((alarms.ov_channels | alarms.or_channels) != 0u)
        return -2; /* frozen capture may be saturated */

    return 0;
}
```

## 8. Vivado 集成

1. 把本目录全部 `.v` 文件加入 Vivado Design Sources。
2. 将 `top_agc_axi` 设为 AGC 外设顶层或封装为自定义 IP。
3. 把 `s_axi_*` 接到 Zynq UltraScale+ MPSoC 的 AXI Master/SmartConnect。
4. 在 Address Editor 分配至少 32 字节地址空间。
5. `s_axi_aclk`、`s_axi_aresetn` 同时驱动 AXI 寄存器和 AGC 核。
6. 将 `adc_ov/or/th1/th2[7:0]` 接到 RFDC 对应报警输出。
7. 将 8 个 DSA code 和 4 个 update 输出接到 RFDC 实时 DSA 控制端口。
8. 将 `adc_clear_ov/or[7:0]` 接回 RFDC 清除端口。
9. 为报警输入 CDC 同步器添加第一阶段 D 引脚的 false-path 约束，并检查 `ASYNC_REG` 属性是否在综合网表中保留。
10. 重新进行综合、实现、时序收敛和硬件联调。

## 9. 时钟与复位假设

- `top_agc_axi` 是单时钟设计，AXI 和 AGC 控制逻辑均使用 `s_axi_aclk`。
- 外部 RFDC 报警可能异步，进入检测器后使用独立单比特 2FF 同步。
- 多比特 DSA 状态没有跨时钟，因为寄存器映射与 AGC 核同域。
- `s_axi_aresetn` 为低有效复位。当前 RTL 多处采用异步拉低、时钟边沿释放的写法；系统顶层应保证复位释放满足目标器件和时钟域要求。

## 10. 人工审核重点与已知限制

人工审核时建议重点检查以下项目：

1. RFDC DSA 码方向是否确实符合当前 RFDC IP 配置。若硬件语义不是 `27-code`，必须修改转换器。
2. `DSA_RANGE_DB=27`、`DSA_STEP_DB=1` 是否与实际 RFDC/外部 DSA 器件一致。
3. OV、OR、TH1、TH2 的极性和“TH2 全通道过弱”定义是否与 RFDC 输出定义一致。
4. 外部报警必须保持足够长。2FF 电平同步器可能漏掉短于一个 `s_axi_aclk` 周期的窄脉冲；若 RFDC 输出是窄脉冲，应在源时钟域做脉冲展宽或事件握手。
5. 当前所有通道共用一个 DSA 值，任何一路强信号都会降低所有通道增益。
6. 冻结确认延迟固定为 4 个周期，与当前 FSM、转换器、fanout 的寄存器层数绑定。修改流水线后必须同步修改并重新仿真。
7. `up_axi.v` 没有把 `WSTRB` 传递给 `agc_regmap`，软件必须使用对齐的 32 位整字读写，不能依赖字节写。
8. CONFIG1/CONFIG2 目前只是存储寄存器，没有连接到 FSM 参数。
9. 死区参数是编译期时钟周期数，不会根据时钟频率自动换算；修改 `s_axi_aclk` 后需重新计算实际时间。
10. 设计不直接控制 DMA 启停，只提供冻结请求/确认。DMA 顺序由 ARM 软件负责。
11. 粘滞报警清除时若本周期报警仍存在，该位会立即重新置 1，这是避免丢失活动故障的预期行为。
12. 当前验证覆盖 RTL 编译、顶层展开、冻结保持和 AXI 寄存器访问；上板前仍需进行 RFDC 接口时序、AXI 地址、实际 DSA 方向和模拟链路验证。

## 11. 已完成的验证

使用 Vivado 2022.2 执行过：

- 所有 Verilog 文件编译；
- `top_agc` 和 `top_agc_axi` 静态展开；
- 上电安全最大衰减测试；
- 自动 AGC 调整测试；
- 冻结请求、4 周期确认、冻结期间保持及解冻恢复测试；
- AXI-Lite 写 `CONTROL`、读 `STATUS` 和解冻测试；
- TH2 上电误判回归测试。

仿真通过不等于硬件接口已经确认。人工审核和上板验证仍应按第 10 节逐项执行。
