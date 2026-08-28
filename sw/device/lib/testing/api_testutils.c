// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "sw/device/lib/testing/api_testutils.h"

#include <stdbool.h>
#include <stdint.h>

#include "hw/top/dt/api.h"  // Generated
#include "sw/device/lib/base/math.h"
#include "sw/device/lib/testing/test_framework/check.h"

status_t api_testutils_get_cycles_32_from_us(dt_clock_t dt_clock,
                                             uint64_t microseconds,
                                             uint32_t *cycles) {
  uint64_t rem_out;
  uint64_t cycles_ = udiv64_slow(microseconds * dt_clock_frequency(dt_clock),
                                 1000000, &rem_out);
  if (rem_out > 0) {
    ++cycles_;
  }
  TRY_CHECK(cycles_ <= UINT32_MAX,
            "The value 0x%08x%08x can't fit into the 32 bits timer counter.",
            (uint32_t)(cycles_ >> 32), (uint32_t)cycles_);
  *cycles = (uint32_t)cycles_;
  return OK_STATUS();
}

status_t api_testutils_get_cycles_64_from_us(dt_clock_t dt_clock,
                                             uint64_t microseconds,
                                             uint64_t *cycles) {
  uint64_t rem_out;
  *cycles = udiv64_slow(microseconds * dt_clock_frequency(dt_clock), 1000000,
                        &rem_out);
  if (rem_out > 0) {
    ++(*cycles);
  }
  return OK_STATUS();
}

status_t api_testutils_get_us_from_cycles(dt_clock_t dt_clock, uint64_t cycles,
                                          uint32_t *us) {
  uint64_t rem_out;
  uint64_t uss =
      udiv64_slow(cycles * 1000000, dt_clock_frequency(dt_clock), &rem_out);
  if (rem_out > 0) {
    ++uss;
  }
  TRY_CHECK(uss <= UINT32_MAX,
            "The value 0x%08x%08x can't fit into the 32 bits timer counter.",
            (uint32_t)(uss >> 32), (uint32_t)uss);
  *us = (uint32_t)uss;
  return OK_STATUS();
}

status_t api_testutils_cycles_spanning_micros(dt_clock_t dt_clock,
                                              uint32_t proposed_cycles,
                                              uint64_t micros,
                                              uint32_t *spanning_cycles) {
  *spanning_cycles = proposed_cycles;
  if (micros > 0) {
    uint32_t cycles_for_micros;
    CHECK_STATUS_OK(api_testutils_get_cycles_32_from_us(dt_clock, micros,
                                                        &cycles_for_micros));
    if (proposed_cycles < cycles_for_micros) {
      *spanning_cycles = cycles_for_micros;
    }
  }
  return OK_STATUS();
}

status_t api_testutils_convert_cycles(dt_clock_t dt_clock_src,
                                      dt_clock_t dt_clock_tgt,
                                      uint32_t src_cycles,
                                      uint32_t *tgt_cycles) {
  uint32_t micros;
  TRY(api_testutils_get_us_from_cycles(dt_clock_src, src_cycles, &micros));
  TRY(api_testutils_get_cycles_32_from_us(dt_clock_tgt, micros, tgt_cycles));
  return OK_STATUS();
}
