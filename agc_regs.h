#ifndef AGC_REGS_H
#define AGC_REGS_H

#include <stdint.h>

#define AGC_REG_COMMAND_OFFSET       0x00u
#define AGC_REG_ALARMS_OFFSET        0x04u
#define AGC_REG_CONFIG1_OFFSET       0x08u
#define AGC_REG_CONFIG2_OFFSET       0x0cu
#define AGC_REG_SCRATCH_OFFSET       0x10u
#define AGC_REG_CONTROL_OFFSET       0x14u
#define AGC_REG_STATUS_OFFSET        0x18u

#define AGC_CONTROL_FREEZE_REQ       (1u << 0)

#define AGC_STATUS_FREEZE_ACTIVE     (1u << 0)
#define AGC_STATUS_FREEZE_REQUESTED  (1u << 1)
#define AGC_STATUS_ATTEN_SHIFT       2u
#define AGC_STATUS_ATTEN_MASK        (0x1fu << AGC_STATUS_ATTEN_SHIFT)
#define AGC_STATUS_HW_CODE_SHIFT     7u
#define AGC_STATUS_HW_CODE_MASK      (0x1fu << AGC_STATUS_HW_CODE_SHIFT)
#define AGC_STATUS_FSM_SHIFT         12u
#define AGC_STATUS_FSM_MASK          (0x0fu << AGC_STATUS_FSM_SHIFT)

static inline volatile uint32_t *agc_reg_ptr(uintptr_t base, uint32_t offset)
{
    return (volatile uint32_t *)(base + offset);
}

static inline uint32_t agc_read_status(uintptr_t base)
{
    return *agc_reg_ptr(base, AGC_REG_STATUS_OFFSET);
}

static inline uint32_t agc_status_atten_db(uint32_t status)
{
    return (status & AGC_STATUS_ATTEN_MASK) >> AGC_STATUS_ATTEN_SHIFT;
}

static inline uint32_t agc_status_hw_code(uint32_t status)
{
    return (status & AGC_STATUS_HW_CODE_MASK) >> AGC_STATUS_HW_CODE_SHIFT;
}

/*
 * Freeze AGC and return a coherent status word.  Start DMA only after this
 * function returns 0.  timeout_cycles is a CPU polling limit, not PL clocks.
 */
static inline int agc_freeze_for_dma(uintptr_t base,
                                     uint32_t timeout_cycles,
                                     uint32_t *locked_status)
{
    uint32_t status;

    *agc_reg_ptr(base, AGC_REG_CONTROL_OFFSET) = AGC_CONTROL_FREEZE_REQ;
    __sync_synchronize();

    while (timeout_cycles-- != 0u) {
        status = agc_read_status(base);
        if ((status & AGC_STATUS_FREEZE_ACTIVE) != 0u) {
            if (locked_status != (uint32_t *)0)
                *locked_status = status;
            __sync_synchronize();
            return 0;
        }
    }

    return -1;
}

static inline void agc_release_after_dma(uintptr_t base)
{
    __sync_synchronize();
    *agc_reg_ptr(base, AGC_REG_CONTROL_OFFSET) = 0u;
    __sync_synchronize();
}

#endif
