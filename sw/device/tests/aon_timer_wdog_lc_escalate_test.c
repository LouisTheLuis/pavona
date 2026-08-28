// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <assert.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>

#include "hw/top/dt/alert_handler.h"
#include "hw/top/dt/aon_timer.h"
#include "hw/top/dt/pwrmgr.h"
#include "hw/top/dt/rstmgr.h"
#include "hw/top/dt/rv_plic.h"
#include "sw/device/lib/base/macros.h"
#include "sw/device/lib/base/mmio.h"
#include "sw/device/lib/dif/dif_alert_handler.h"
#include "sw/device/lib/dif/dif_aon_timer.h"
#include "sw/device/lib/dif/dif_pwrmgr.h"
#include "sw/device/lib/dif/dif_rstmgr.h"
#include "sw/device/lib/dif/dif_rv_plic.h"
#include "sw/device/lib/dif/dif_rv_timer.h"
#include "sw/device/lib/runtime/irq.h"
#include "sw/device/lib/runtime/log.h"
#include "sw/device/lib/testing/alert_handler_testutils.h"
#include "sw/device/lib/testing/aon_timer_testutils.h"
#include "sw/device/lib/testing/api_testutils.h"
#include "sw/device/lib/testing/rstmgr_testutils.h"
#include "sw/device/lib/testing/test_framework/FreeRTOSConfig.h"
#include "sw/device/lib/testing/test_framework/check.h"
#include "sw/device/lib/testing/test_framework/ottf_main.h"

OTTF_DEFINE_TEST_CONFIG();

/**
 * Program the alert handler to escalate on alerts upto phase 2 (i.e. reset) but
 * the phase 1 (i.e. wipe secrets) should occur and last during the time the
 * wdog is programmed to bark.
 *
 * The escalation times are controlled by alert_handler's clock; there is a
 * busy_spin_micros that should not expire unless the test is not working
 * right, and a watchdog that should not trip either. The delays for all these
 * must be carefully set, but they are based on the cycles for escalation.
 */
enum {
  kMinimumMicros = 5,
  kWdogBarkMicros = 3 * 100,          // 300 us
  kWdogBiteMicros = 4 * 100,          // 400 us
  kEscalationPhase0Micros = 1 * 100,  // 100 us
  // The cpu value is set slightly larger, since if they are the same it is
  // possible busy_spin_micros in execute_test can complete before the
  // interrupt.
  kEscalationPhase0MicrosCpu = kEscalationPhase0Micros + 20,  // 120 us
  kEscalationPhase1Micros = 5 * 100,                          // 500 us
  kEscalationPhase2Micros = 100,                              // 100 us
};

static_assert(
    kWdogBarkMicros < kWdogBiteMicros &&
        kWdogBarkMicros > kEscalationPhase0Micros &&
        kWdogBarkMicros < (kEscalationPhase0Micros + kEscalationPhase1Micros) &&
        kWdogBiteMicros < (kEscalationPhase0Micros + kEscalationPhase1Micros),
    "The wdog bark and bite shall happens during the escalation phase 1");

/**
 * Objects to access the peripherals used in this test via dif API.
 */
enum {
  /**
   * PLIC target for the Ibex core.
   */
  kDtRvPlicTargetIbex0 = 0,
};

static dif_aon_timer_t aon_timer;
static dif_rv_plic_t plic;
static dif_pwrmgr_t pwrmgr;
static dif_rstmgr_t rstmgr;
static dif_alert_handler_t alert_handler;

/**
 * External ISR.
 *
 * Handles all peripheral interrupts on Ibex. PLIC asserts an external interrupt
 * line to the CPU, which results in a call to this OTTF ISR. This ISR
 * overrides the default OTTF implementation.
 */
bool ottf_handle_irq(uint32_t *exc_info, dt_instance_id_t inst_id,
                     dif_rv_plic_irq_id_t plic_irq_id) {
  // Check if this is the AON timer peripheral
  if (inst_id == dt_aon_timer_instance_id(kDtAonTimerAon)) {
    // We should not get aon timer interrupts since escalation suppresses them.
    dt_aon_timer_irq_t irq =
        dt_aon_timer_irq_from_plic_id(kDtAonTimerAon, plic_irq_id);
    LOG_ERROR("Unexpected aon timer interrupt %d", irq);
    return true;
  }

  // Check if this is the alert handler peripheral
  if (inst_id == dt_alert_handler_instance_id(kDtAlertHandler)) {
    // Convert PLIC IRQ ID to alert handler IRQ
    dt_alert_handler_irq_t irq =
        dt_alert_handler_irq_from_plic_id(kDtAlertHandler, plic_irq_id);

    // Check the class.
    dif_alert_handler_class_state_t state;
    CHECK_DIF_OK(dif_alert_handler_get_class_state(
        &alert_handler, kDifAlertHandlerClassA, &state));
    CHECK(state == kDifAlertHandlerClassStatePhase0, "Wrong phase %d", state);

    // Deals with the alert cause: we expect it to be from the pwrmgr.
    dif_alert_handler_alert_t alert =
        dt_pwrmgr_alert_to_alert_id(kDtPwrmgrAon, kDtPwrmgrAlertFatalFault);
    bool is_cause = false;
    CHECK_DIF_OK(
        dif_alert_handler_alert_is_cause(&alert_handler, alert, &is_cause));
    CHECK(is_cause);

    // Acknowledge the cause and irq; neither of them affect escalation.
    CHECK_DIF_OK(dif_alert_handler_alert_acknowledge(&alert_handler, alert));
    CHECK_DIF_OK(
        dif_alert_handler_alert_is_cause(&alert_handler, alert, &is_cause));
    CHECK(!is_cause);

    CHECK_DIF_OK(dif_alert_handler_irq_acknowledge(&alert_handler, irq));
    return true;
  }

  return false;
}

/**
 * Initialize the peripherals used in this test.
 */
void init_peripherals(void) {
  CHECK_DIF_OK(dif_pwrmgr_init_from_dt(kDtPwrmgrAon, &pwrmgr));
  CHECK_DIF_OK(dif_rstmgr_init_from_dt(kDtRstmgrAon, &rstmgr));
  CHECK_DIF_OK(dif_aon_timer_init_from_dt(kDtAonTimerAon, &aon_timer));
  CHECK_DIF_OK(dif_rv_plic_init_from_dt(kDtRvPlic, &plic));
  CHECK_DIF_OK(dif_alert_handler_init_from_dt(kDtAlertHandler, &alert_handler));

  // Enable AON timer interrupts in PLIC
  dt_plic_irq_id_t wkup_irq = dt_aon_timer_irq_to_plic_id(
      kDtAonTimerAon, kDtAonTimerIrqWkupTimerExpired);
  dt_plic_irq_id_t bark_irq =
      dt_aon_timer_irq_to_plic_id(kDtAonTimerAon, kDtAonTimerIrqWdogTimerBark);

  dt_plic_irq_id_t aon_irq_ids[] = {wkup_irq, bark_irq};
  for (size_t i = 0; i < ARRAYSIZE(aon_irq_ids); ++i) {
    CHECK_DIF_OK(dif_rv_plic_irq_set_priority(&plic, aon_irq_ids[i],
                                              /*priority=*/1u));
    CHECK_DIF_OK(dif_rv_plic_irq_set_enabled(
        &plic, aon_irq_ids[i], kDtRvPlicTargetIbex0, kDifToggleEnabled));
  }

  CHECK_DIF_OK(dif_rv_plic_target_set_threshold(&plic, kDtRvPlicTargetIbex0,
                                                /*threshold=*/0u));
}

// Based on the escalation phase 0, the aon timer bark is set to 1.5
// the corresponding delay, the bite to twice that amount, and the
// next escalation phase to 3 times the phase 0 cycles. The wait in
// micros is set to 1.25 the escalation phase 0.
static void compute_delays(uint32_t *escalation_0_cycles, uint32_t *bark_cycles,
                           uint32_t *wait_us) {
  // Base line is the alert_handler cycles to escalation 0. It should
  // translate to at least 5 micros.
  uint32_t proposed_phase_0_cycles = 250;
  dt_clock_t dt_alert_handler_clk =
      dt_alert_handler_clock((dt_alert_handler_t)0, kDtAlertHandlerClockClk);
  CHECK_STATUS_OK(api_testutils_cycles_spanning_micros(
      dt_alert_handler_clk, proposed_phase_0_cycles, kMinimumMicros,
      escalation_0_cycles));
  uint32_t phase_0_micros;
  CHECK_STATUS_OK(api_testutils_get_us_from_cycles(
      dt_alert_handler_clk, *escalation_0_cycles, &phase_0_micros));
  dt_clock_t dt_aon_clk =
      dt_aon_timer_clock(kDtAonTimerAon, kDtAonTimerClockAon);
  // bark_us set to 1.5 phase_0_micros.
  uint64_t bark_us = (uint64_t)(phase_0_micros + (phase_0_micros >> 1));
  CHECK_STATUS_OK(
      api_testutils_get_cycles_32_from_us(dt_aon_clk, bark_us, bark_cycles));
  LOG_INFO("phase_0_micros %d, bark_us %d (0x%0x%0x), bark_cycles %d",
           phase_0_micros, (uint32_t)bark_us, (uint32_t)(bark_us >> 32),
           (uint32_t)bark_us, *bark_cycles);
  // The phase_0_micros is required to span at least kMinimumMicros.
  *wait_us = phase_0_micros + (phase_0_micros >> 2);
  LOG_INFO(
      "Cycles proposed %d, esc_0 %d, micros %d, wait_micros %d, bark_cycles %d",
      proposed_phase_0_cycles, *escalation_0_cycles, phase_0_micros, *wait_us,
      *bark_cycles);
}

/**
 * Program the alert handler to escalate on alerts upto phase 2 (i.e. reset) but
 * the phase 1 (i.e. wipe secrets) should occur and last during the time the
 * wdog is programed to bark.
 */
static void alert_handler_config(uint32_t escalation_0_cycles) {
  dif_alert_handler_alert_t alerts[] = {
      dt_pwrmgr_alert_to_alert_id(kDtPwrmgrAon, kDtPwrmgrAlertFatalFault)};
  dif_alert_handler_class_t alert_classes[] = {kDifAlertHandlerClassA};

  dif_alert_handler_escalation_phase_t esc_phases[] = {
      {.phase = kDifAlertHandlerClassStatePhase0,
       .signal = 0,
       .duration_cycles = escalation_0_cycles},
      {.phase = kDifAlertHandlerClassStatePhase1,
       .signal = 1,
       .duration_cycles = 4 * escalation_0_cycles},
      {.phase = kDifAlertHandlerClassStatePhase2,
       .signal = 3,
       .duration_cycles = escalation_0_cycles}};

  dif_alert_handler_class_config_t class_config[] = {{
      .auto_lock_accumulation_counter = kDifToggleDisabled,
      .accumulator_threshold = 0,
      .irq_deadline_cycles = escalation_0_cycles,
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
static void execute_test(dif_aon_timer_t *aon_timer, uint32_t bark_cycles,
                         uint32_t wait_micros) {
  uint32_t bite_cycles = 2 * bark_cycles;
  LOG_INFO("Wdog will bark after %u cycles and bite after %u cycles",
           bark_cycles, bite_cycles);

  // Setup the wdog bark and bite timeouts.
  CHECK_STATUS_OK(
      aon_timer_testutils_watchdog_config(aon_timer, bark_cycles, bite_cycles,
                                          /*pause_in_sleep=*/false));

  // Trigger the alert handler to escalate.
  dif_pwrmgr_alert_t alert = kDifPwrmgrAlertFatalFault;
  CHECK_DIF_OK(dif_pwrmgr_alert_force(&pwrmgr, alert));
  busy_spin_micros(wait_micros);

  // This should never run since escalation turns the CPU off.
  CHECK(false, "The alert handler failed to escalate");
}

bool test_main(void) {
  // Enable global and external IRQ at Ibex.
  irq_global_ctrl(true);
  irq_external_ctrl(true);

  init_peripherals();

  // Enable all the alert handler interrupts used in this test.
  dt_plic_irq_id_t classa_irq = dt_alert_handler_irq_to_plic_id(
      kDtAlertHandler, kDtAlertHandlerIrqClassa);
  dt_plic_irq_id_t classb_irq = dt_alert_handler_irq_to_plic_id(
      kDtAlertHandler, kDtAlertHandlerIrqClassb);
  dt_plic_irq_id_t classc_irq = dt_alert_handler_irq_to_plic_id(
      kDtAlertHandler, kDtAlertHandlerIrqClassc);
  dt_plic_irq_id_t classd_irq = dt_alert_handler_irq_to_plic_id(
      kDtAlertHandler, kDtAlertHandlerIrqClassd);

  dt_plic_irq_id_t alert_irq_ids[] = {classa_irq, classb_irq, classc_irq,
                                      classd_irq};
  for (size_t i = 0; i < ARRAYSIZE(alert_irq_ids); ++i) {
    CHECK_DIF_OK(dif_rv_plic_irq_set_priority(&plic, alert_irq_ids[i],
                                              /*priority=*/1u));
    CHECK_DIF_OK(dif_rv_plic_irq_set_enabled(
        &plic, alert_irq_ids[i], kDtRvPlicTargetIbex0, kDifToggleEnabled));
  }

  uint32_t escalation_0_cycles;
  uint32_t bark_cycles;
  uint32_t wait_micros;
  compute_delays(&escalation_0_cycles, &bark_cycles, &wait_micros);

  alert_handler_config(escalation_0_cycles);

  // Check if there was a HW reset caused by the escalation.
  dif_rstmgr_reset_info_bitfield_t rst_info;
  rst_info = rstmgr_testutils_reason_get();
  rstmgr_testutils_reason_clear();

  CHECK(rst_info == kDifRstmgrResetInfoPor ||
            rst_info == kDifRstmgrResetInfoEscalation,
        "Wrong reset reason %02X", rst_info);

  if (rst_info == kDifRstmgrResetInfoPor) {
    LOG_INFO("Booting for the first time, starting test");
    execute_test(&aon_timer, bark_cycles, wait_micros);
  } else if (rst_info == kDifRstmgrResetInfoEscalation) {
    LOG_INFO("Booting for the second time due to escalation reset");

    return true;
  } else {
    LOG_ERROR("Unexpected rst_info=0x%x", rst_info);
  }
  return false;
}
