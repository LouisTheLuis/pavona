// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef OPENTITAN_SW_DEVICE_LIB_TESTING_API_TESTUTILS_H_
#define OPENTITAN_SW_DEVICE_LIB_TESTING_API_TESTUTILS_H_

#include <stdint.h>

#include "hw/top/dt/api.h"
#include "sw/device/lib/base/status.h"

/**
 * Compute the dt_clock's cycles spanning the given microseconds.
 *
 * @param dt_clock The clock.
 * @param microseconds The number of microseconds.
 * @param[out] cycles The number of clock cycles as a uint32_t.
 * @return The result of the operation.
 */
OT_WARN_UNUSED_RESULT
status_t api_testutils_get_cycles_32_from_us(dt_clock_t dt_clock,
                                             uint64_t microseconds,
                                             uint32_t *cycles);

/**
 * Compute the dt_clock's cycles spanning the given microseconds.
 *
 * @param dt_clock The clock.
 * @param microseconds The number of microseconds.
 * @param[out] cycles The number of clock cycles as a uint64_t.
 * @return The result of the operation.
 */
OT_WARN_UNUSED_RESULT
status_t api_testutils_get_cycles_64_from_us(dt_clock_t dt_clock,
                                             uint64_t microseconds,
                                             uint64_t *cycles);

/**
 * Compute the number of microseconds spanning the dt_clock's cycles.
 *
 * @param dt_clock The clock.
 * @param cycles The number of clock cycles.
 * @param[out] microseconds The number of microseconds.
 * @return The result of the operation.
 */
OT_WARN_UNUSED_RESULT
status_t api_testutils_get_us_from_cycles(dt_clock_t dt_clock, uint64_t cycles,
                                          uint32_t *microseconds);

/**
 * Compute the dt_clock's cycles that span at least the given microseconds.
 *
 * The computed cycles must be greater or equal to the proposed cycles.
 *
 * @param dt_clock The clock.
 * @param proposed_cycles The proposed number of clock cycles.
 * @param microseconds The number of microseconds that must be spanned.
 * @param[out] spanning_cycles The possibly higher cycle count that spans
 *             the required microseconds.
 * @return The result of the operation.
 */
OT_WARN_UNUSED_RESULT
status_t api_testutils_cycles_spanning_micros(dt_clock_t dt_clock,
                                              uint32_t proposed_cycles,
                                              uint64_t microseconds,
                                              uint32_t *spanning_cycles);

/**
 * Convert cycles to different clock.
 *
 * @param dt_clock_src The source clock.
 * @param dt_clock_tgt The target clock.
 * @param cycles The number of source clock cycles.
 * @param[out] target_cycles The target cycle count that spans
 *             the required source cycles.
 * @return The result of the operation.
 */
OT_WARN_UNUSED_RESULT
status_t api_testutils_convert_cycles(dt_clock_t dt_clock_src,
                                      dt_clock_t dt_clock_tgt, uint32_t cycles,
                                      uint32_t *target_cycles);

#endif  // OPENTITAN_SW_DEVICE_LIB_TESTING_API_TESTUTILS_H_
