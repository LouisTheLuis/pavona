// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "sw/device/lib/dif/dif_pinmux.h"
#include "sw/device/lib/dif/dif_pwrmgr.h"
#include "sw/device/lib/dif/dif_rv_plic.h"
#include "sw/device/lib/runtime/ibex.h"
#include "sw/device/lib/runtime/irq.h"
#include "sw/device/lib/runtime/log.h"
#include "sw/device/lib/testing/aon_timer_testutils.h"
#include "sw/device/lib/testing/pwrmgr_testutils.h"
#include "sw/device/lib/testing/rstmgr_testutils.h"
#include "sw/device/lib/testing/rv_plic_testutils.h"
#include "sw/device/lib/testing/test_framework/check.h"
#include "sw/device/lib/testing/test_framework/ottf_main.h"
#include "sw/device/lib/testing/test_framework/ottf_utils.h"
#include "sw/device/lib/testing/test_framework/status.h"

#include "hw/top/pwrmgr_regs.h"

#if (HAS_SYSRST_CTRL)
#include "sw/device/lib/dif/dif_sysrst_ctrl.h"
#endif
#if defined(OPENTITAN_IS_DRAGONFLY)
#include "sw/device/lib/dif/dif_gpio.h"
#include "sw/device/lib/testing/rand_testutils.h"
#endif

/*
 * RV_DM access after wakeup test.
 */

OTTF_DEFINE_TEST_CONFIG(.enable_uart_flow_control = true);

enum {
  kSoftwareBarrierTimeoutUsec = 1000000,
  kPlicTarget = 0,
};

// Handles shared with the interrupt handler.
dif_rv_plic_t rv_plic;
dif_pinmux_t pinmux;
dif_pwrmgr_t pwrmgr;
#if (HAS_SYSRST_CTRL)
dif_sysrst_ctrl_t sysrst_ctrl;
#endif
#if defined(OPENTITAN_IS_DRAGONFLY)
static dif_gpio_t gpio;
#endif

// This variable will be updated by the DV environment.
OT_SECTION(".rodata")
static volatile const uint8_t kSoftwareBarrier = 0;

// This variable will be updated by the test host.
OT_SECTION(".data")
static volatile const uint8_t kSoftwareBarrierHost = 0;

static_assert(kDtPwrmgrCount == 1, "this test expects exactly one pwrmgr");
static const dt_pwrmgr_t kPwrmgrDt = 0;
static_assert(kDtRvPlicCount == 1, "this test expects exactly one rv_plic");
static const dt_rv_plic_t kRvPlicDt = 0;
#if (HAS_SYSRST_CTRL)
static_assert(kDtSysrstCtrlCount >= 1,
              "this test expects at least one sysrst_ctrl");
static const dt_sysrst_ctrl_t kSysrstCtrlDt = 0;
#endif
static_assert(kDtPinmuxCount == 1, "this test expects exactly one pinmux");
static const dt_pinmux_t kPinmuxDt = 0;
#if defined(OPENTITAN_IS_DRAGONFLY)
static const dt_gpio_t kGpioDt = 0;
static_assert(kDtGpioCount == 1, "this test expects exactly one gpio");
// Pinmux wakeup detector used to wake the chip from the GPIO pin.
enum { kWakeupDetectorId = 0 };

// GPIO pads the test drives. The wakeup pad is the one right after them.
int num_gpio_pads;
unsigned gpio_mask;
static int first_gpio_pin;
#endif

#if defined(OPENTITAN_IS_EGRET)
/**
 * External interrupt handler.
 *
 * Simply claim the interrupt and does nothing else.
 */
void ottf_external_isr(uint32_t *exc_info) {
  dif_rv_plic_irq_id_t plic_irq_id;
  CHECK_DIF_OK(dif_rv_plic_irq_claim(&rv_plic, kPlicTarget, &plic_irq_id));
}
#elif defined(OPENTITAN_IS_DRAGONFLY)
/**
 * Handles the pwrmgr wakeup interrupt.
 *
 * The OTTF external handler claims the interrupt, calls this, and completes it
 * when this returns true, so the wakeup cause and the pwrmgr interrupt are all
 * that need clearing here.
 */
bool ottf_handle_irq(uint32_t *exc_info, dt_instance_id_t devid,
                     dif_rv_plic_irq_id_t irq_id) {
  if (devid == dt_pwrmgr_instance_id(kPwrmgrDt) &&
      irq_id == dt_pwrmgr_irq_to_plic_id(kPwrmgrDt, kDtPwrmgrIrqWakeup)) {
    CHECK_DIF_OK(dif_pinmux_wakeup_cause_clear(&pinmux));
    CHECK_DIF_OK(dif_pwrmgr_irq_acknowledge(&pwrmgr, kDtPwrmgrIrqWakeup));
    return true;
  }
  return false;
}
#else
#error "Unrecognized Top Configuration"
#endif

/**
 * Put the device to sleep.
 *
 * @param pwrmgr A handle to the power manager.
 * @param deep_sleep Whether or not to enter a deep sleep.
 */
static void put_to_sleep(dif_pwrmgr_t *pwrmgr, bool deep_sleep) {
  dif_pwrmgr_domain_config_t cfg;
  CHECK_DIF_OK(dif_pwrmgr_get_domain_config(pwrmgr, &cfg));
  if (deep_sleep) {
    cfg &= ~kDifPwrmgrDomainOptionMainPowerInLowPower;
  } else {
    cfg |= kDifPwrmgrDomainOptionMainPowerInLowPower;
  }

  dif_pwrmgr_request_sources_t wakeup_sources;
#if (HAS_SYSRST_CTRL)
  CHECK_DIF_OK(dif_pwrmgr_find_request_source(
      pwrmgr, kDifPwrmgrReqTypeWakeup,
      dt_sysrst_ctrl_instance_id(kSysrstCtrlDt), kDtSysrstCtrlWakeupWkupReq,
      &wakeup_sources));
#elif defined(OPENTITAN_IS_DRAGONFLY)
  // Clear any wakeup the detector latched before we armed low power. A stale
  // cause makes pwrmgr leave low power again as soon as it enters.
  CHECK_DIF_OK(dif_pinmux_wakeup_cause_clear(&pinmux));
  CHECK_DIF_OK(dif_pwrmgr_find_request_source(
      pwrmgr, kDifPwrmgrReqTypeWakeup, dt_pinmux_instance_id(kPinmuxDt),
      kDtPinmuxWakeupPinWkupReq, &wakeup_sources));
#else
#error "Unrecognized Top Configuration"
#endif
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, wakeup_sources, cfg));
  LOG_INFO("%s",
           deep_sleep ? "Entering deep sleep." : "Entering normal sleep.");
  wait_for_interrupt();
}

bool test_main(void) {
#if defined(OPENTITAN_IS_DRAGONFLY)
  num_gpio_pads = 8;
  gpio_mask = (1 << num_gpio_pads) - 1;
  // The GPIOs are DIOs on Dragonfly.
  first_gpio_pin = kTopDragonflyDirectPadsGpioGpio0;
  dif_pinmux_wakeup_config_t wakeup_cfg;
#endif

  // Enable global and external IRQ at Ibex.
  irq_global_ctrl(true);
  irq_external_ctrl(true);

  // Initialize pinmux, pwrmgr, and RV Plic
  CHECK_DIF_OK(dif_pinmux_init_from_dt(kPinmuxDt, &pinmux));
  CHECK_DIF_OK(dif_pwrmgr_init_from_dt(kPwrmgrDt, &pwrmgr));
  CHECK_DIF_OK(dif_rv_plic_init_from_dt(kRvPlicDt, &rv_plic));
#if (HAS_SYSRST_CTRL)
  CHECK_DIF_OK(dif_sysrst_ctrl_init_from_dt(kSysrstCtrlDt, &sysrst_ctrl));
#endif
#if defined(OPENTITAN_IS_DRAGONFLY)
  CHECK_DIF_OK(dif_gpio_init_from_dt(kGpioDt, &gpio));
#endif

  const volatile uint8_t *const software_barrier =
      (kDeviceType == kDeviceSimDV) ? &kSoftwareBarrier : &kSoftwareBarrierHost;

  switch (rstmgr_testutils_reason_get()) {
    case kDifRstmgrResetInfoPor:  // The first power-up.
      LOG_INFO("Software Setup.");
      // Wait for sequence to run its checks.
      OTTF_WAIT_FOR(*software_barrier == 1, kSoftwareBarrierTimeoutUsec);

      // Enable all the AON interrupts used in this test.
      dif_rv_plic_irq_id_t plic_id =
          dt_pwrmgr_irq_to_plic_id(kPwrmgrDt, kDtPwrmgrIrqWakeup);
      rv_plic_testutils_irq_range_enable(&rv_plic, kPlicTarget, plic_id,
                                         plic_id);

      // Enable pwrmgr interrupt.
      CHECK_DIF_OK(dif_pwrmgr_irq_set_enabled(&pwrmgr, kDifPwrmgrIrqWakeup,
                                              kDifToggleEnabled));

#if defined(OPENTITAN_IS_DRAGONFLY)
      // Wake on a rising edge of the pad after the tested GPIOs.
      wakeup_cfg.mode = kDifPinmuxWakeupModePositiveEdge;
      wakeup_cfg.signal_filter = false;
      wakeup_cfg.pad_type = kDifPinmuxPadKindDio;
      wakeup_cfg.pad_select =
          (dif_pinmux_index_t)(first_gpio_pin + num_gpio_pads);
      // Arm the detector. Filling in the config on its own leaves the pinmux
      // with no wakeup source, so the chip never leaves low power.
      CHECK_DIF_OK(dif_pinmux_wakeup_detector_enable(&pinmux, kWakeupDetectorId,
                                                     wakeup_cfg));
#endif

#if (HAS_SYSRST_CTRL)
      // Set up power button as wake up source.
      dif_sysrst_ctrl_input_change_config_t config = {
          .input_changes = kDifSysrstCtrlInputPowerButtonH2L,
          .debounce_time_threshold = 1,  // 5us
      };
      CHECK_DIF_OK(
          dif_sysrst_ctrl_input_change_detect_configure(&sysrst_ctrl, config));
      CHECK_DIF_OK(dif_pinmux_mio_select_input(
          &pinmux,
          dt_sysrst_ctrl_periph_io(kSysrstCtrlDt, kDtSysrstCtrlPeriphIoPwrbIn),
          kDtPadIor13));
#elif defined(OPENTITAN_IS_DRAGONFLY)
      // The GPIOs are DIOs, so they need no pinmux selection.
      CHECK_DIF_OK(
          dif_gpio_output_set_enabled_all(&gpio, (dif_gpio_state_t)gpio_mask));
      CHECK_DIF_OK(dif_gpio_write_masked(&gpio, (dif_gpio_mask_t)gpio_mask,
                                         (dif_gpio_state_t)0x00000000));

      uint8_t gpio_val = (uint8_t)(rand_testutils_gen32_range(0, gpio_mask));
      CHECK_DIF_OK(dif_gpio_write_masked(&gpio, (dif_gpio_mask_t)gpio_mask,
                                         (dif_gpio_state_t)gpio_val));

      // The sequence waits for this exact prefix.
      LOG_INFO("Chosen GPIO value: %2x", gpio_val);

#else
#error "Unrecognized top configuration"
#endif

      // Put the device in a normal sleep.
      put_to_sleep(&pwrmgr, /*deep_sleep=*/false);
      LOG_INFO("Waking up from normal sleep.");
#if (HAS_SYSRST_CTRL)
      // Clean up wakeup source after sleep.
      CHECK_DIF_OK(dif_sysrst_ctrl_ulp_wakeup_clear_status(&sysrst_ctrl));
#elif defined(OPENTITAN_IS_DRAGONFLY)
      // When running outside DV, wait until the host is ready to end this
      // round.
      bool end_round = false;
      if (kDeviceType != kDeviceSimDV)
        do {
          CHECK_DIF_OK(
              dif_gpio_read(&gpio, (dif_gpio_pin_t)num_gpio_pads, &end_round));
        } while (!end_round);
#else
#error "Unrecognized Top Configuration"
#endif

      // Wait for sequence to run its checks.
      OTTF_WAIT_FOR(*software_barrier == 2, kSoftwareBarrierTimeoutUsec);

#if defined(OPENTITAN_IS_DRAGONFLY)
      // Dragonfly has no deep sleep, so the test ends here.
      return true;
#endif
#if defined(OPENTITAN_IS_EGRET)
      // Put the device in a deep sleep.
      put_to_sleep(&pwrmgr, /*deep_sleep=*/true);
#endif

      break;

    case kDifRstmgrResetInfoLowPowerExit:  // The power up after deep sleep.
      LOG_INFO("Waking up from deep sleep.");

      // Wait for sequence to finish before returning.
      OTTF_WAIT_FOR(*software_barrier == 3, kSoftwareBarrierTimeoutUsec);
      return true;

    default:
      LOG_ERROR("Device was reset by an unexpected source.");
      break;
  }
  return false;
}
