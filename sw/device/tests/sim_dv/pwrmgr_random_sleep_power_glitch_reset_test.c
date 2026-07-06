// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <assert.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>

#if defined(OPENTITAN_IS_EGRET)
#include "hw/top/dt/adc_ctrl.h"
#endif
#include "sw/device/lib/base/abs_mmio.h"
#include "sw/device/lib/base/math.h"
#include "sw/device/lib/base/mmio.h"
#include "sw/device/lib/dif/dif_alert_handler.h"
#include "sw/device/lib/dif/dif_aon_timer.h"
#if defined(OPENTITAN_IS_EGRET)
#include "sw/device/lib/dif/dif_flash_ctrl.h"
#endif
#include "sw/device/lib/dif/dif_pinmux.h"
#include "sw/device/lib/dif/dif_pwrmgr.h"
#include "sw/device/lib/dif/dif_rstmgr.h"
#include "sw/device/lib/dif/dif_rv_plic.h"
#include "sw/device/lib/dif/dif_rv_timer.h"
#if defined(OPENTITAN_IS_EGRET)
#include "sw/device/lib/dif/dif_sysrst_ctrl.h"
#endif
#include "sw/device/lib/runtime/irq.h"
#include "sw/device/lib/runtime/log.h"
#include "sw/device/lib/testing/alert_handler_testutils.h"
#include "sw/device/lib/testing/aon_timer_testutils.h"
#if defined(OPENTITAN_IS_EGRET)
#include "sw/device/lib/testing/flash_ctrl_testutils.h"
#include "sw/device/lib/testing/nv_counter_testutils.h"
#endif
#include "sw/device/lib/testing/pwrmgr_testutils.h"
#include "sw/device/lib/testing/ret_sram_testutils.h"
#include "sw/device/lib/testing/rstmgr_testutils.h"
#include "sw/device/lib/testing/rv_plic_testutils.h"
#include "sw/device/lib/testing/test_framework/FreeRTOSConfig.h"
#include "sw/device/lib/testing/test_framework/check.h"
#include "sw/device/lib/testing/test_framework/ottf_main.h"

#if defined(OPENTITAN_IS_EGRET)
#include "hw/top_egret/sw/autogen/top_egret.h"
#elif defined(OPENTITAN_IS_DRAGONFLY)
#include "hw/top_dragonfly/sw/autogen/top_dragonfly.h"
#endif

OTTF_DEFINE_TEST_CONFIG();
#if defined(OPENTITAN_IS_EGRET)
static volatile const uint8_t RST_IDX[12] = {0, 1, 2, 3, 4,  5,
                                             6, 7, 8, 9, 10, 11};

static const uint32_t kPlicTarget = kTopEgretPlicTargetIbex0;
#elif defined(OPENTITAN_IS_DRAGONFLY)
static volatile const uint8_t RST_IDX[6] = {0, 1, 2, 3, 4, 5};

static const uint32_t kPlicTarget = kTopDragonflyPlicTargetIbex0;
#endif

/**
 * Objects to access the peripherals used in this test via dif API.
 */
#if defined(OPENTITAN_IS_EGRET)
static dif_flash_ctrl_state_t flash_ctrl;
#endif
static dif_rv_plic_t plic;
static dif_alert_handler_t alert_handler;
static dif_aon_timer_t aon_timer;
static dif_pwrmgr_t pwrmgr;
static dif_rstmgr_t rstmgr;

#if defined(OPENTITAN_IS_EGRET)
static const dt_adc_ctrl_t kAdcCtrlDt = 0;
static_assert(kDtAdcCtrlCount == 1, "this test expects an adc_ctrl");
#endif
static const dt_rstmgr_t kRstmgrDt = 0;
static_assert(kDtRstmgrCount == 1, "this test expects a rstmgr");
static const dt_pwrmgr_t kPwrmgrDt = 0;
static_assert(kDtPwrmgrCount == 1, "this test expects a pwrmgr");
static const dt_aon_timer_t kAonTimerDt = 0;
static_assert(kDtAonTimerCount == 1, "this test expects an aon_timer");
static const dt_rv_plic_t kRvPlicDt = 0;
static_assert(kDtRvPlicCount >= 1, "this test expects at least one rv_plic");
#if defined(OPENTITAN_IS_EGRET)
static const dt_flash_ctrl_t kFlashCtrlDt = 0;
static_assert(kDtFlashCtrlCount >= 1,
              "this test expects at least one flash_ctrl");
#endif
static const dt_alert_handler_t kAlertHandlerDt = 0;
static_assert(kDtAlertHandlerCount == 1,
              "this library expects exactly one alert_handler");

dif_pwrmgr_request_sources_t aon_timer_wakeup_sources;
#if defined(OPENTITAN_IS_EGRET)
dif_pwrmgr_request_sources_t adc_ctrl_wakeup_sources;
#endif
dif_pwrmgr_request_sources_t all_wakeup_sources;
dif_pwrmgr_request_sources_t wdog_reset_sources;

/**
 * Program the alert handler to escalate on alerts upto phase 2 (i.e. reset) but
 * the phase 1 (i.e. wipe secrets) should occur and last during the time the
 * wdog is programed to bark.
 */
enum {
  kWdogBarkMicros = 3 * 100,          // 300 us
  kWdogBiteMicros = 4 * 100,          // 400 us
  kEscalationPhase0Micros = 1 * 100,  // 100 us
  // The cpu value is slightly larger as the busy_spin_micros
  // routine cycle count comes out slightly smaller due to the
  // fact that it does not divide by exactly 1M
  // see sw/device/lib/runtime/hart.c
  kEscalationPhase0MicrosCpu = kEscalationPhase0Micros + 20,  // 120 us
  kEscalationPhase1Micros = 5 * 100,                          // 500 us
  kEscalationPhase2Micros = 50,                               // 50 us
};

#if defined(OPENTITAN_IS_DRAGONFLY)
// NVM counters/fields to keep test steps between deep sleep modes
enum {
  // The counter ID for the non-volatile counter keeping the test steps.
  kCounterEventIdx = 0
};

// To keep track of the test steps
static uint32_t event_idx = 0;
#endif

static_assert(
    kWdogBarkMicros < kWdogBiteMicros &&
        kWdogBarkMicros > kEscalationPhase0Micros &&
        kWdogBarkMicros < (kEscalationPhase0Micros + kEscalationPhase1Micros) &&
        kWdogBiteMicros < (kEscalationPhase0Micros + kEscalationPhase1Micros),
    "The wdog bark and bite shall happens during the escalation phase 1");

/**
 * External ISR.
 *
 * Handles all peripheral interrupts on Ibex. PLIC asserts an external interrupt
 * line to the CPU, which results in a call to this OTTF ISR. This ISR
 * overrides the default OTTF implementation.
 */
void ottf_external_isr(uint32_t *exc_info) {
#if defined(OPENTITAN_IS_EGRET)
  top_egret_plic_peripheral_t peripheral;
#elif defined(OPENTITAN_IS_DRAGONFLY)
  top_dragonfly_plic_peripheral_t peripheral;
#endif
  dif_rv_plic_irq_id_t irq_id;
  uint32_t irq = 0;
  uint32_t alert = 0;

  CHECK_DIF_OK(dif_rv_plic_irq_claim(&plic, kPlicTarget, &irq_id));

#if defined(OPENTITAN_IS_EGRET)
  peripheral = (top_egret_plic_peripheral_t)
      top_egret_plic_interrupt_for_peripheral[irq_id];

  if (peripheral == kTopEgretPlicPeripheralAonTimerAon) {
    irq =
        (dif_aon_timer_irq_t)(irq_id -
                              (dif_rv_plic_irq_id_t)
                                  kTopEgretPlicIrqIdAonTimerAonWkupTimerExpired);

    // Stops escalation process.
    CHECK_DIF_OK(dif_alert_handler_escalation_clear(&alert_handler,
                                                    kDifAlertHandlerClassA));
    CHECK_DIF_OK(dif_aon_timer_irq_acknowledge(&aon_timer, irq));

    CHECK(irq != kTopEgretPlicIrqIdAonTimerAonWdogTimerBark,
          "AON Timer Wdog should not bark");

  } else if (peripheral == kTopEgretPlicPeripheralAlertHandler) {
    irq = (dif_rv_plic_irq_id_t)(irq_id -
                                 (dif_rv_plic_irq_id_t)
                                     kTopEgretPlicIrqIdAlertHandlerClassa);
#elif defined(OPENTITAN_IS_DRAGONFLY)
  peripheral = (top_dragonfly_plic_peripheral_t)
      top_dragonfly_plic_interrupt_for_peripheral[irq_id];

  if (peripheral == kTopDragonflyPlicPeripheralAonTimerAon) {
    irq =
        (dif_aon_timer_irq_t)(irq_id -
                              (dif_rv_plic_irq_id_t)
                                  kTopDragonflyPlicIrqIdAonTimerAonWkupTimerExpired);

    // Stops escalation process.
    CHECK_DIF_OK(dif_alert_handler_escalation_clear(&alert_handler,
                                                    kDifAlertHandlerClassA));
    CHECK_DIF_OK(dif_aon_timer_irq_acknowledge(&aon_timer, irq));

    CHECK(irq != kTopDragonflyPlicIrqIdAonTimerAonWdogTimerBark,
          "AON Timer Wdog should not bark");

  } else if (peripheral == kTopDragonflyPlicPeripheralAlertHandler) {
    irq = (dif_rv_plic_irq_id_t)(irq_id -
                                 (dif_rv_plic_irq_id_t)
                                     kTopDragonflyPlicIrqIdAlertHandlerClassa);
#endif
    CHECK_DIF_OK(dif_alert_handler_alert_acknowledge(&alert_handler, alert));

    dif_alert_handler_class_state_t state;
    CHECK_DIF_OK(dif_alert_handler_get_class_state(
        &alert_handler, kDifAlertHandlerClassA, &state));

    CHECK(state == kDifAlertHandlerClassStatePhase0, "Wrong phase %d", state);

    CHECK_DIF_OK(dif_alert_handler_irq_acknowledge(&alert_handler, irq));
  }

  // Complete the IRQ by writing the IRQ source to the Ibex specific CC
  // register.
  CHECK_DIF_OK(dif_rv_plic_irq_complete(&plic, kPlicTarget, irq_id));
}

/**
 * Initialize the peripherals used in this test.
 */
void init_peripherals(void) {
  // Initialize pwrmgr.
  CHECK_DIF_OK(dif_pwrmgr_init_from_dt(kPwrmgrDt, &pwrmgr));

  // Initialize rstmgr to check the reset reason.
  CHECK_DIF_OK(dif_rstmgr_init_from_dt(kRstmgrDt, &rstmgr));

  // Initialize aon timer to use the wdog.
  CHECK_DIF_OK(dif_aon_timer_init_from_dt(kAonTimerDt, &aon_timer));
  CHECK_DIF_OK(dif_pwrmgr_find_request_source(
      &pwrmgr, kDifPwrmgrReqTypeWakeup, dt_aon_timer_instance_id(kAonTimerDt),
      kDtAonTimerWakeupWkupReq, &aon_timer_wakeup_sources));

#if defined(OPENTITAN_IS_EGRET)
  // Initialize flash_ctrl
  CHECK_DIF_OK(dif_flash_ctrl_init_state_from_dt(&flash_ctrl, kFlashCtrlDt));
#endif

  // Initialize plic.
  CHECK_DIF_OK(dif_rv_plic_init_from_dt(kRvPlicDt, &plic));

#if defined(OPENTITAN_IS_EGRET)
  rv_plic_testutils_irq_range_enable(
      &plic, kPlicTarget, kTopEgretPlicIrqIdAonTimerAonWkupTimerExpired,
      kTopEgretPlicIrqIdAonTimerAonWdogTimerBark);
#elif defined(OPENTITAN_IS_DRAGONFLY)
  rv_plic_testutils_irq_range_enable(
      &plic, kPlicTarget, kTopDragonflyPlicIrqIdAonTimerAonWkupTimerExpired,
      kTopDragonflyPlicIrqIdAonTimerAonWdogTimerBark);
#endif

  // Initialize alert handler.
  CHECK_DIF_OK(dif_alert_handler_init_from_dt(kAlertHandlerDt, &alert_handler));

  // Other wakeups.
#if defined(OPENTITAN_IS_EGRET)
  CHECK_DIF_OK(dif_pwrmgr_find_request_source(
      &pwrmgr, kDifPwrmgrReqTypeWakeup, dt_adc_ctrl_instance_id(kAdcCtrlDt),
      kDtAdcCtrlWakeupWkupReq, &adc_ctrl_wakeup_sources));
#endif
  CHECK_DIF_OK(dif_pwrmgr_find_request_source(
      &pwrmgr, kDifPwrmgrReqTypeReset, dt_aon_timer_instance_id(kDtAonTimerAon),
      kDtAonTimerResetReqAonTimer, &wdog_reset_sources));
  CHECK_DIF_OK(dif_pwrmgr_get_all_request_sources(
      &pwrmgr, kDifPwrmgrReqTypeWakeup, &all_wakeup_sources));
}

/**
 * Program the alert handler to escalate on alerts upto phase 2 (i.e. reset) but
 * the phase 1 (i.e. wipe secrets) should occur and last during the time the
 * wdog is programed to bark.
 */
static void alert_handler_config(void) {
#if defined(OPENTITAN_IS_EGRET)
  dif_alert_handler_alert_t alerts[] = {kTopEgretAlertIdPwrmgrAonFatalFault};
#elif defined(OPENTITAN_IS_DRAGONFLY)
  dif_alert_handler_alert_t alerts[] = {
      kTopDragonflyAlertIdPwrmgrAonFatalFault};
#endif
  dif_alert_handler_class_t alert_classes[] = {kDifAlertHandlerClassA};

  uint32_t cycles[3] = {0};
  CHECK_STATUS_OK(alert_handler_testutils_get_cycles_from_us(
      kEscalationPhase0Micros, &cycles[0]));
  CHECK_STATUS_OK(alert_handler_testutils_get_cycles_from_us(
      kEscalationPhase1Micros, &cycles[1]));
  CHECK_STATUS_OK(alert_handler_testutils_get_cycles_from_us(
      kEscalationPhase2Micros, &cycles[2]));

  dif_alert_handler_escalation_phase_t esc_phases[] = {
      {.phase = kDifAlertHandlerClassStatePhase0,
       .signal = 0,
       .duration_cycles =
           cycles[0] * alert_handler_testutils_cycle_rescaling_factor()},
      {.phase = kDifAlertHandlerClassStatePhase1,
       .signal = 1,
       .duration_cycles =
           cycles[1] * alert_handler_testutils_cycle_rescaling_factor()},
      {.phase = kDifAlertHandlerClassStatePhase2,
       .signal = 3,
       .duration_cycles =
           cycles[2] * alert_handler_testutils_cycle_rescaling_factor()}};

  dif_alert_handler_class_config_t class_config[] = {{
      .auto_lock_accumulation_counter = kDifToggleDisabled,
      .accumulator_threshold = 0,
      .irq_deadline_cycles =
          cycles[0] * alert_handler_testutils_cycle_rescaling_factor(),
      .escalation_phases = esc_phases,
      .escalation_phases_len = ARRAYSIZE(esc_phases),
      .crashdump_escalation_phase = kDifAlertHandlerClassStatePhase3,
  }};

  dif_alert_handler_class_t classes[] = {kDifAlertHandlerClassA};
  dif_alert_handler_config_t config = {
      .alerts = alerts,
      .alert_classes = alert_classes,
      .alerts_len = ARRAYSIZE(alerts),
      .classes = classes,
      .class_configs = class_config,
      .classes_len = ARRAYSIZE(class_config),
      .ping_timeout = kAlertHandlerTestutilsDefaultPingTimeout,
  };

  CHECK_STATUS_OK(alert_handler_testutils_configure_all(&alert_handler, config,
                                                        kDifToggleEnabled));
  // Enables alert handler irq.
  CHECK_DIF_OK(dif_alert_handler_irq_set_enabled(
      &alert_handler, kDifAlertHandlerIrqClassa, kDifToggleEnabled));
}

/**
 * Execute the aon timer interrupt test.
 */
static void config_escalate(dif_aon_timer_t *aon_timer,
                            const dif_pwrmgr_t *pwrmgr) {
  uint32_t bark_cycles = 0;
  CHECK_STATUS_OK(aon_timer_testutils_get_aon_cycles_32_from_us(kWdogBarkMicros,
                                                                &bark_cycles));
  bark_cycles *= alert_handler_testutils_cycle_rescaling_factor();
  uint32_t bite_cycles = 0;
  CHECK_STATUS_OK(aon_timer_testutils_get_aon_cycles_32_from_us(kWdogBiteMicros,
                                                                &bite_cycles));
  bite_cycles *= alert_handler_testutils_cycle_rescaling_factor();

  LOG_INFO(
      "Wdog will bark after %u/%u us/cycles and bite after %u/%u us/cycles",
      (uint32_t)kWdogBarkMicros, (uint32_t)bark_cycles,
      (uint32_t)kWdogBiteMicros, (uint32_t)bite_cycles);

  // Setup the wdog bark and bite timeouts.
  CHECK_STATUS_OK(aon_timer_testutils_watchdog_config(aon_timer, bark_cycles,
                                                      bite_cycles, false));

  // Trigger the alert handler to escalate.
  dif_pwrmgr_alert_t alert = kDifPwrmgrAlertFatalFault;
  CHECK_DIF_OK(dif_pwrmgr_alert_force(pwrmgr, alert));
}

static void low_power_glitch_reset(const dif_pwrmgr_t *pwrmgr) {
  // Program the pwrmgr to go to deep sleep state (clocks off).
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, aon_timer_wakeup_sources, 0));
  // Enter in low power mode.
  wait_for_interrupt();
}

static void normal_sleep_glitch_reset(const dif_pwrmgr_t *pwrmgr) {
  // Place device into normal (shallow) power
  dif_pwrmgr_domain_config_t config;
#if defined(OPENTITAN_IS_EGRET)
  config = kDifPwrmgrDomainOptionUsbClockInLowPower |
           kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#elif defined(OPENTITAN_IS_DRAGONFLY)
  config = kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#endif
  CHECK_STATUS_OK(pwrmgr_testutils_enable_low_power(
      pwrmgr, aon_timer_wakeup_sources, config));
  // Enter in low power mode.
  wait_for_interrupt();
}

static void timer_on(uint32_t usec) {
  busy_spin_micros(usec);
  // If we arrive here the test must fail.
  CHECK(false, "Timeout waiting for reset!");
}

/**
 * Configure the wdog.
 */
static void config_wdog(const dif_aon_timer_t *aon_timer,
                        const dif_pwrmgr_t *pwrmgr, uint64_t bark_time_us,
                        uint64_t bite_time_us) {
  uint32_t bark_cycles = 0;
  CHECK_STATUS_OK(aon_timer_testutils_get_aon_cycles_32_from_us(bark_time_us,
                                                                &bark_cycles));
  uint32_t bite_cycles = 0;
  CHECK_STATUS_OK(aon_timer_testutils_get_aon_cycles_32_from_us(bite_time_us,
                                                                &bite_cycles));

  LOG_INFO("Wdog will bark after %u us and bite after %u us",
           (uint32_t)bark_time_us, (uint32_t)bite_time_us);
  // Setup the wdog bark and bite timeouts.

  CHECK_STATUS_OK(aon_timer_testutils_watchdog_config(aon_timer, bark_cycles,
                                                      bite_cycles, false));
  // Set wdog as a reset source.
  CHECK_DIF_OK(dif_pwrmgr_set_request_sources(
      pwrmgr, kDifPwrmgrReqTypeReset, wdog_reset_sources, kDifToggleEnabled));
}

/**
 * Execute the aon timer wdog bite reset during sleep test.
 */
static void sleep_wdog_bite_test(const dif_aon_timer_t *aon_timer,
                                 const dif_pwrmgr_t *pwrmgr,
                                 uint64_t bark_time_us) {
  uint64_t bite_time_us = bark_time_us * 2;
  config_wdog(aon_timer, pwrmgr, bark_time_us, bite_time_us);
}

static void low_power_wdog(const dif_pwrmgr_t *pwrmgr) {
  // Program the pwrmgr to go to deep sleep state (clocks off).
  // Enter in low power mode.
#if defined(OPENTITAN_IS_EGRET)
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, adc_ctrl_wakeup_sources, 0));
#endif
  LOG_INFO("Low power set for watch dog");
  wait_for_interrupt();
  // If we arrive here the test must fail.
  CHECK(false, "Fail to enter in low power mode!");
}

static void normal_sleep_wdog(const dif_pwrmgr_t *pwrmgr) {
  // Place device into low power and immediately wake.
  dif_pwrmgr_domain_config_t config;
#if defined(OPENTITAN_IS_EGRET)
  config = kDifPwrmgrDomainOptionUsbClockInLowPower |
           kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#elif defined(OPENTITAN_IS_DRAGONFLY)
  config = kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#endif

  // Enter in low power mode.
#if defined(OPENTITAN_IS_EGRET)
  CHECK_STATUS_OK(pwrmgr_testutils_enable_low_power(
      pwrmgr, adc_ctrl_wakeup_sources, config));
#elif defined(OPENTITAN_IS_DRAGONFLY)
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, wdog_reset_sources, config));
#endif
  LOG_INFO("Normal sleep set for watchdog");
  wait_for_interrupt();
}

static void low_power_por(const dif_pwrmgr_t *pwrmgr) {
  // Set por as a reset source.
  CHECK_DIF_OK(dif_pwrmgr_set_request_sources(
      pwrmgr, kDifPwrmgrReqTypeReset, wdog_reset_sources, kDifToggleEnabled));

  // Program the pwrmgr to go to deep sleep state (clocks off).
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, all_wakeup_sources, 0));
  // Enter in low power mode.
  wait_for_interrupt();
  // If we arrive here the test must fail.
  CHECK(false, "Fail to enter in low power mode!");
}

static void normal_sleep_por(const dif_pwrmgr_t *pwrmgr) {
  // Set por as a reset source.
  CHECK_DIF_OK(dif_pwrmgr_set_request_sources(
      pwrmgr, kDifPwrmgrReqTypeReset, wdog_reset_sources, kDifToggleEnabled));

  // Place device into low power and immediately wake.
  dif_pwrmgr_domain_config_t config;
#if defined(OPENTITAN_IS_EGRET)
  config = kDifPwrmgrDomainOptionUsbClockInLowPower |
           kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#elif defined(OPENTITAN_IS_DRAGONFLY)
  config = kDifPwrmgrDomainOptionCoreClockInLowPower |
           kDifPwrmgrDomainOptionIoClockInLowPower |
           kDifPwrmgrDomainOptionMainPowerInLowPower;
#endif

  // Program the pwrmgr to go to swallow sleep state (clocks on).
  CHECK_STATUS_OK(
      pwrmgr_testutils_enable_low_power(pwrmgr, all_wakeup_sources, config));
  // Enter in low power mode.
  wait_for_interrupt();
}

bool test_main(void) {
  // Enable global and external IRQ at Ibex.
  irq_global_ctrl(true);
  irq_external_ctrl(true);

#if defined(OPENTITAN_IS_DRAGONFLY)
  ret_sram_testutils_init();
#endif
  init_peripherals();

  // Enable all the AON interrupts used in this test.
#if defined(OPENTITAN_IS_EGRET)
  rv_plic_testutils_irq_range_enable(&plic, kPlicTarget,
                                     kTopEgretPlicIrqIdAlertHandlerClassa,
                                     kTopEgretPlicIrqIdAlertHandlerClassd);
#elif defined(OPENTITAN_IS_DRAGONFLY)
  rv_plic_testutils_irq_range_enable(&plic, kPlicTarget,
                                     kTopDragonflyPlicIrqIdAlertHandlerClassa,
                                     kTopDragonflyPlicIrqIdAlertHandlerClassd);
#endif

  alert_handler_config();

  // Egret still uses flash_ctrl as it is non-volatile and can be used to test
  // with POR in the middle of the test, whereas retention SRAM cannot be
#if defined(OPENTITAN_IS_EGRET)
  // First check the flash stored value
  uint32_t event_idx = 0;
  CHECK_STATUS_OK(flash_ctrl_testutils_counter_get(0, &event_idx));

  // Enable flash access
  CHECK_STATUS_OK(
      flash_ctrl_testutils_default_region_access(&flash_ctrl,
                                                 /*rd_en*/ true,
                                                 /*prog_en*/ true,
                                                 /*erase_en*/ true,
                                                 /*scramble_en*/ false,
                                                 /*ecc_en*/ false,
                                                 /*he_en*/ false));

  // Increment flash counter to know where we are
  CHECK_STATUS_OK(flash_ctrl_testutils_counter_increment(&flash_ctrl, 0));

  LOG_INFO("Test round %d", event_idx);
  LOG_INFO("RST_IDX[%d] = %d", event_idx, RST_IDX[event_idx]);
#endif

  // Check if there was a HW reset caused by expected cases
  dif_rstmgr_reset_info_bitfield_t rst_info;
  rst_info = rstmgr_testutils_reason_get();
  rstmgr_testutils_reason_clear();
  LOG_INFO("reset info = %02X", rst_info);

  // Dragonfly uses retention SRAM instead of flash_ctrl as it does not have
  // flash. Retention SRAM will retain state between resets excluding POR.
#if defined(OPENTITAN_IS_DRAGONFLY)
  if (rst_info == kDifRstmgrResetInfoPor) {
    CHECK_STATUS_OK(ret_sram_testutils_counter_clear(kCounterEventIdx));
  }

  // First check the ret_sram stored value
  CHECK_STATUS_OK(ret_sram_testutils_counter_get(kCounterEventIdx, &event_idx));

  // Increment ret_sram counter to know where we are
  CHECK_STATUS_OK(ret_sram_testutils_counter_increment(kCounterEventIdx));

  LOG_INFO("Test round %d", event_idx);
  LOG_INFO("RST_IDX[%d] = %d", event_idx, RST_IDX[event_idx]);
#endif

  CHECK(rst_info == kDifRstmgrResetInfoPor ||
  // SysRstCtrl is not used in Dragonfly
#if defined(OPENTITAN_IS_EGRET)
            rst_info == kDifRstmgrResetInfoSysRstCtrl ||
#endif
            rst_info == kDifRstmgrResetInfoWatchdog ||
            rst_info == kDifRstmgrResetInfoEscalation ||
            rst_info == kDifRstmgrResetInfoLowPowerExit ||
#if defined(OPENTITAN_IS_EGRET)
            rst_info == (kDifRstmgrResetInfoSysRstCtrl |
                         kDifRstmgrResetInfoLowPowerExit) ||
#endif
            rst_info == (kDifRstmgrResetInfoPowerUnstable |
                         kDifRstmgrResetInfoLowPowerExit) ||
            rst_info == (kDifRstmgrResetInfoPowerUnstable |
                         kDifRstmgrResetInfoWatchdog |
                         kDifRstmgrResetInfoLowPowerExit) ||
            rst_info == (kDifRstmgrResetInfoPowerUnstable |
                         kDifRstmgrResetInfoWatchdog) ||
            rst_info == kDifRstmgrResetInfoPowerUnstable ||
            rst_info ==
                (kDifRstmgrResetInfoPor | kDifRstmgrResetInfoLowPowerExit) ||
            rst_info == (kDifRstmgrResetInfoWatchdog |
                         kDifRstmgrResetInfoLowPowerExit) ||
            rst_info == (kDifRstmgrResetInfoEscalation |
                         kDifRstmgrResetInfoLowPowerExit) ||
            rst_info == kDifRstmgrResetInfoSw,
        "Wrong reset reason %02X", rst_info);

#if defined(OPENTITAN_IS_EGRET)
  switch (RST_IDX[event_idx] / 2) {
    case 0:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO("Booting and setting normal sleep followed by glitch reset");
        LOG_INFO("Let SV wait timer reset");
        normal_sleep_glitch_reset(&pwrmgr);
        timer_on(kWdogBiteMicros);
      } else {
        LOG_INFO("Booting and setting deep sleep followed by glitch reset");
        LOG_INFO("Let SV wait timer reset");
        low_power_glitch_reset(&pwrmgr);
      }
      break;
    case 1:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO("Booting and setting normal sleep followed by hw por");
        LOG_INFO("Let SV wait timer reset");
        normal_sleep_por(&pwrmgr);
        timer_on(kWdogBiteMicros);
      } else {
        LOG_INFO("Booting and setting deep sleep followed by hw por");
        LOG_INFO("Let SV wait timer reset");
        low_power_por(&pwrmgr);
      }
      break;
    case 2:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO(
            "Booting and setting normal sleep mode followed for low_power "
            "entry reset");
        LOG_INFO("Let SV wait timer reset");
        // actually the same test as normal sleep + watchdog
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        normal_sleep_wdog(&pwrmgr);
        timer_on(kEscalationPhase0MicrosCpu);
      } else {
        LOG_INFO(
            "Booting and setting deep sleep mode followed for low_power entry "
            "reset");
        LOG_INFO("Let SV wait timer reset");
        // Executing the wdog bite reset during sleep test.
        // actually the same test as deep sleep + watchdog
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        low_power_wdog(&pwrmgr);
      }
      break;

    case 3:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO(
            "Booting and setting normal sleep followed by watchdog reset "
            "combined "
            "with sw_req");
        LOG_INFO("Let SV wait timer reset");
        // Executing the wdog bite reset during sleep test.
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        CHECK_DIF_OK(dif_rstmgr_software_device_reset(&rstmgr));
        LOG_INFO("Device reset from sw");
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        normal_sleep_wdog(&pwrmgr);
        timer_on(kEscalationPhase0MicrosCpu);
      } else {
        LOG_INFO(
            "Booting and setting deep sleep followed by watchdog reset "
            "combined "
            "with sw_req");
        LOG_INFO("Let SV wait timer reset");
        // Executing the wdog bite reset during sleep test.
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        CHECK_DIF_OK(dif_rstmgr_software_device_reset(&rstmgr));
        LOG_INFO("Device reset from sw");
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        low_power_wdog(&pwrmgr);
      }
      break;
    case 4:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO("Booting and setting normal sleep followed by watchdog reset");
        LOG_INFO("Let SV wait timer reset");
        // Executing the wdog bite reset during sleep test.
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        normal_sleep_wdog(&pwrmgr);
        timer_on(kEscalationPhase0MicrosCpu);
      } else {
        LOG_INFO("Booting and setting deep sleep followed by watchdog reset");
        LOG_INFO("Let SV wait timer reset");
        // Executing the wdog bite reset during sleep test.
        CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
        sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
        low_power_wdog(&pwrmgr);
      }
      break;
    case 5:
      if (RST_IDX[event_idx] % 2) {
        LOG_INFO("Last Booting");

        return true;
      } else {
        LOG_INFO(
            "Booting and running normal sleep followed by escalation reset");
        config_escalate(&aon_timer, &pwrmgr);
        timer_on(kEscalationPhase0MicrosCpu);
      }
      break;
    default:
      LOG_INFO("Booting for undefined case");
  }
// Dragonfly uses its own case block due to the absence of deep sleep and
// non-volatile memory
#elif defined(OPENTITAN_IS_DRAGONFLY)
  switch (RST_IDX[event_idx]) {
    case 0:
      LOG_INFO("Booting and setting normal sleep followed by glitch reset");
      LOG_INFO("Let SV wait timer reset");
      normal_sleep_glitch_reset(&pwrmgr);
      timer_on(kWdogBiteMicros);
      break;

    case 1:
      LOG_INFO(
          "Booting and setting normal sleep mode followed for low_power "
          "entry reset");
      LOG_INFO("Let SV wait timer reset");
      // actually the same test as normal sleep + watchdog
      CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
      sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
      normal_sleep_wdog(&pwrmgr);
      timer_on(kEscalationPhase0MicrosCpu);
      break;

    case 2:
      LOG_INFO(
          "Booting and setting normal sleep followed by watchdog reset "
          "combined "
          "with sw_req");
      LOG_INFO("Let SV wait timer reset");
      // Executing the wdog bite reset during sleep test.
      CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
      CHECK_DIF_OK(dif_rstmgr_software_device_reset(&rstmgr));
      LOG_INFO("Device reset from sw");
      sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
      normal_sleep_wdog(&pwrmgr);
      timer_on(kEscalationPhase0MicrosCpu);
      break;

    case 3:
      LOG_INFO("Booting and setting normal sleep followed by watchdog reset");
      LOG_INFO("Let SV wait timer reset");
      // Executing the wdog bite reset during sleep test.
      CHECK_STATUS_OK(rstmgr_testutils_pre_reset(&rstmgr));
      sleep_wdog_bite_test(&aon_timer, &pwrmgr, 200);
      normal_sleep_wdog(&pwrmgr);
      timer_on(kEscalationPhase0MicrosCpu);
      break;

    case 4:
      LOG_INFO("Booting and running normal sleep followed by escalation reset");
      config_escalate(&aon_timer, &pwrmgr);
      timer_on(kEscalationPhase0MicrosCpu);
      break;

    case 5:
      LOG_INFO("Last Booting");
      return true;
      break;

    default:
      LOG_INFO("Booting for undefined case");
  }
#endif

  return false;
}
