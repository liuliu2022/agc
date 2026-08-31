#ifndef AGC_REGS_H
#define AGC_REGS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AGC_REG_COMMAND_OFFSET       0x00u
#define AGC_REG_ALARMS_OFFSET        0x04u
#define AGC_REG_CONFIG1_OFFSET       0x08u
#define AGC_REG_CONFIG2_OFFSET       0x0cu
#define AGC_REG_SCRATCH_OFFSET       0x10u
#define AGC_REG_CONTROL_OFFSET       0x14u
#define AGC_REG_STATUS_OFFSET        0x18u

#define AGC_COMMAND_CLEAR_OV         (1u << 0)
#define AGC_COMMAND_CLEAR_OR         (1u << 1)
#define AGC_COMMAND_CLEAR_TH1        (1u << 2)
#define AGC_COMMAND_CLEAR_TH2        (1u << 3)
#define AGC_COMMAND_CLEAR_ALL        0x0fu

#define AGC_CONTROL_FREEZE_REQ       (1u << 0)

#define AGC_STATUS_FREEZE_ACTIVE     (1u << 0)
#define AGC_STATUS_FREEZE_REQUESTED  (1u << 1)
#define AGC_STATUS_ATTEN_SHIFT       2u
#define AGC_STATUS_ATTEN_MASK        (0x1fu << AGC_STATUS_ATTEN_SHIFT)
#define AGC_STATUS_HW_CODE_SHIFT     7u
#define AGC_STATUS_HW_CODE_MASK      (0x1fu << AGC_STATUS_HW_CODE_SHIFT)
#define AGC_STATUS_FSM_SHIFT         12u
#define AGC_STATUS_FSM_MASK          (0x0fu << AGC_STATUS_FSM_SHIFT)

#define AGC_ALARMS_OV_SHIFT          0u
#define AGC_ALARMS_OR_SHIFT          8u
#define AGC_ALARMS_TH1_SHIFT         16u
#define AGC_ALARMS_TH2_SHIFT         24u

typedef struct {
    uint32_t raw;
    uint8_t freeze_active;
    uint8_t freeze_requested;
    uint8_t attenuation_db;
    uint8_t hardware_dsa_code;
    uint8_t fsm_state;
} agc_status_t;

typedef struct {
    uint32_t raw;
    uint8_t ov_channels;
    uint8_t or_channels;
    uint8_t th1_channels;
    uint8_t th2_channels;
} agc_alarms_t;

uint32_t agc_reg_read(uintptr_t base, uint32_t offset);
void agc_reg_write(uintptr_t base, uint32_t offset, uint32_t value);

uint32_t agc_read_status_raw(uintptr_t base);
agc_status_t agc_decode_status(uint32_t raw_status);
agc_status_t agc_read_status(uintptr_t base);

uint32_t agc_read_alarms_raw(uintptr_t base);
agc_alarms_t agc_decode_alarms(uint32_t raw_alarms);
agc_alarms_t agc_read_alarms(uintptr_t base);
void agc_clear_alarms(uintptr_t base, uint32_t clear_mask);

/*
 * Request a frozen DSA state and wait for the hardware acknowledgement.
 * timeout_polls is a CPU polling count, not a PL clock count.
 * Returns 0 on success and -1 on timeout.
 */
int agc_freeze_for_dma(uintptr_t base,
                       uint32_t timeout_polls,
                       agc_status_t *locked_status);

void agc_release_after_dma(uintptr_t base);

#ifdef __cplusplus
}
#endif

#endif
