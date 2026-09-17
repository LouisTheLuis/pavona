// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The register software writes to raise an interrupt without a cause behind it. It hands the device
// a write enable one cycle wide, so what is worth checking is that the pulse reaches the state it
// is meant to set. A checker built on transactions cannot see this cleanly: it learns of the write
// when the transfer is answered, after the device acted on it, and of the effect from a separate
// stream with no order against the first.
//
// There is no companion assertion for the alert test register: the alert sender shares one state
// machine between alerts and pings, so how long a test alert takes to reach the wire is not a
// number this interface can state.
interface pwrmgr_intr_sva_if (
  input logic clk_i,
  input logic rst_ni,
  // The interrupt test register and the state it is meant to set.
  input logic intr_test_q,
  input logic intr_test_qe,
  input logic intr_state_q
);

  bit disable_sva;

  // Writing the interrupt test register sets the interrupt state on the next cycle. The device
  // takes the write enable directly, so there is nothing between the two but the flop.
  `ASSERT(IntrTestSetsState_A, intr_test_qe && intr_test_q |=> intr_state_q, clk_i,
          !rst_ni || disable_sva)

endinterface : pwrmgr_intr_sva_if
