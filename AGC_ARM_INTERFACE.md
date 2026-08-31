# AGC ARM control interface

The register map uses byte offsets from the AXI-Lite base address.

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x00` | COMMAND | WO | Bits `[3:0]` clear OV/OR/TH1/TH2 sticky alarms |
| `0x04` | ALARMS | RO | Four 8-bit per-channel sticky alarm vectors |
| `0x08` | CONFIG1 | RW | Reserved configuration register |
| `0x0c` | CONFIG2 | RW | Reserved configuration register |
| `0x10` | SCRATCH | RW | AXI link test register |
| `0x14` | CONTROL | RW | Bit 0: AGC freeze request |
| `0x18` | STATUS | RO | Freeze acknowledgement and current DSA state |

`STATUS` layout for `CODE_WIDTH=5`:

- bit 0: `freeze_active`
- bit 1: `freeze_requested`
- bits 6:2: current intuitive attenuation in dB
- bits 11:7: current RFDC hardware DSA code
- bits 15:12: AGC FSM state

## DMA sequence

1. Write `CONTROL.bit0 = 1`.
2. Poll `STATUS.bit0` until it becomes 1.
3. Read `STATUS`; the attenuation and hardware DSA code are now stable.
4. Start DMA and keep `CONTROL.bit0` set for the whole transfer.
5. Stop/complete DMA, then write `CONTROL.bit0 = 0` to resume automatic AGC.
6. Read `ALARMS` after DMA to decide whether the frozen capture experienced
   OV/OR/threshold events.

The freeze acknowledgement is delayed by four PL clocks so any DSA update
already in the FSM/converter/fanout pipeline reaches every RFDC port first.
Alarm sticky bits continue recording while DSA is frozen.

## Required wiring

For a new Vivado integration, instantiate `top_agc_axi.v`; it already connects
`up_axi`, `agc_regmap` and `top_agc` in the same `s_axi_aclk` domain. Connect
its `s_axi_*` interface to the Zynq UltraScale+ MPSoC AXI master and assign an
address in Vivado Address Editor.

If the three modules are integrated separately, connect these ports:

Connect these ports at the integration level:

```text
agc_regmap.agc_freeze_req       -> top_agc.agc_freeze_req
top_agc.agc_freeze_active      -> agc_regmap.agc_freeze_active
top_agc.current_atten_db       -> agc_regmap.current_atten_db
top_agc.current_hw_dsa_code    -> agc_regmap.current_hw_dsa_code
top_agc.current_fsm_state      -> agc_regmap.current_fsm_state
```

This direct connection requires `agc_regmap.up_clk` and `top_agc.clk` to be
the same clock domain.  If they are different, use a request/acknowledge CDC
snapshot bridge instead of synchronizing the multi-bit status bus bit by bit.
