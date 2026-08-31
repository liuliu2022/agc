#include "agc_regs.h"

static void agc_memory_barrier(void)
{
    __sync_synchronize();
}

uint32_t agc_reg_read(uintptr_t base, uint32_t offset)
{
    volatile const uint32_t *reg = (volatile const uint32_t *)(base + offset);
    uint32_t value = *reg;
    agc_memory_barrier();
    return value;
}

void agc_reg_write(uintptr_t base, uint32_t offset, uint32_t value)
{
    volatile uint32_t *reg = (volatile uint32_t *)(base + offset);
    *reg = value;
    agc_memory_barrier();
}

uint32_t agc_read_status_raw(uintptr_t base)
{
    return agc_reg_read(base, AGC_REG_STATUS_OFFSET);
}

agc_status_t agc_decode_status(uint32_t raw_status)
{
    agc_status_t status;

    status.raw = raw_status;
    status.freeze_active =
        (uint8_t)((raw_status & AGC_STATUS_FREEZE_ACTIVE) != 0u);
    status.freeze_requested =
        (uint8_t)((raw_status & AGC_STATUS_FREEZE_REQUESTED) != 0u);
    status.attenuation_db = (uint8_t)(
        (raw_status & AGC_STATUS_ATTEN_MASK) >> AGC_STATUS_ATTEN_SHIFT);
    status.hardware_dsa_code = (uint8_t)(
        (raw_status & AGC_STATUS_HW_CODE_MASK) >> AGC_STATUS_HW_CODE_SHIFT);
    status.fsm_state = (uint8_t)(
        (raw_status & AGC_STATUS_FSM_MASK) >> AGC_STATUS_FSM_SHIFT);

    return status;
}

agc_status_t agc_read_status(uintptr_t base)
{
    return agc_decode_status(agc_read_status_raw(base));
}

uint32_t agc_read_alarms_raw(uintptr_t base)
{
    return agc_reg_read(base, AGC_REG_ALARMS_OFFSET);
}

agc_alarms_t agc_decode_alarms(uint32_t raw_alarms)
{
    agc_alarms_t alarms;

    alarms.raw = raw_alarms;
    alarms.ov_channels = (uint8_t)(raw_alarms >> AGC_ALARMS_OV_SHIFT);
    alarms.or_channels = (uint8_t)(raw_alarms >> AGC_ALARMS_OR_SHIFT);
    alarms.th1_channels = (uint8_t)(raw_alarms >> AGC_ALARMS_TH1_SHIFT);
    alarms.th2_channels = (uint8_t)(raw_alarms >> AGC_ALARMS_TH2_SHIFT);

    return alarms;
}

agc_alarms_t agc_read_alarms(uintptr_t base)
{
    return agc_decode_alarms(agc_read_alarms_raw(base));
}

void agc_clear_alarms(uintptr_t base, uint32_t clear_mask)
{
    agc_reg_write(base,
                  AGC_REG_COMMAND_OFFSET,
                  clear_mask & AGC_COMMAND_CLEAR_ALL);
}

int agc_freeze_for_dma(uintptr_t base,
                       uint32_t timeout_polls,
                       agc_status_t *locked_status)
{
    agc_status_t status;

    agc_reg_write(base, AGC_REG_CONTROL_OFFSET, AGC_CONTROL_FREEZE_REQ);

    while (timeout_polls-- != 0u) {
        status = agc_read_status(base);
        if (status.freeze_active != 0u) {
            if (locked_status != (agc_status_t *)0)
                *locked_status = status;
            return 0;
        }
    }

    return -1;
}

void agc_release_after_dma(uintptr_t base)
{
    agc_reg_write(base, AGC_REG_CONTROL_OFFSET, 0u);
}
