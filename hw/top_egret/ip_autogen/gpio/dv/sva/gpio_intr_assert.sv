// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Cycle level properties of the interrupt path.
//
// These live here rather than in the scoreboard because every relationship below is between
// signals of one clock domain in one cycle. A scoreboard sees the register content and the bus
// access on two analysis ports with no ordering between them, so it can only approximate when a
// write took effect; an assertion sees the write enable and the register in the same cycle and
// does not have to.
//
// The contract checked is the one prim_intr_hw states for an Event type interrupt: the state
// bit is set when the event occurs and stays set until software writes one to clear it. The
// four detection modes are the ones the register description defines.
module gpio_intr_assert #(
  parameter int unsigned NumIOs = 32
) (
  input logic                clk_i,
  input logic                rst_ni,

  // The filtered input the interrupt logic keys off.
  input logic [NumIOs-1:0]   data_in,

  // Interrupt configuration and state, as the device holds them.
  input logic [NumIOs-1:0]   intr_state,
  input logic [NumIOs-1:0]   intr_enable,
  input logic [NumIOs-1:0]   en_rising,
  input logic [NumIOs-1:0]   en_falling,
  input logic [NumIOs-1:0]   en_lvlhigh,
  input logic [NumIOs-1:0]   en_lvllow,

  // The software write to INTR_STATE, seen in the cycle it lands.
  input logic                intr_state_we,
  input logic [NumIOs-1:0]   intr_state_wd,

  // INTR_TEST is write only and its written value is an event for that cycle alone.
  input logic                intr_test_qe,
  input logic [NumIOs-1:0]   intr_test_q,

  input logic [NumIOs-1:0]   intr_o
);

  // The previous filtered input, for the edge modes. Kept here rather than taken from the
  // design so that the property does not depend on the design's own edge detection.
  logic [NumIOs-1:0] data_in_prev;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) data_in_prev <= '0;
    else         data_in_prev <= data_in;
  end

  for (genvar i = 0; i < NumIOs; i++) begin : gen_intr_assert
    logic event_i;
    logic sw_clear_i;

    // One event per detection mode the register description defines, plus the test write.
    assign event_i = (en_rising[i]  &  data_in[i] & ~data_in_prev[i]) |
                     (en_falling[i] & ~data_in[i] &  data_in_prev[i]) |
                     (en_lvlhigh[i] &  data_in[i])                    |
                     (en_lvllow[i]  & ~data_in[i])                    |
                     (intr_test_qe  &  intr_test_q[i]);

    assign sw_clear_i = intr_state_we & intr_state_wd[i];

    // Set on the event. Software clearing in the same cycle wins, which is how
    // prim_subreg_arb resolves a hardware set against a write of one.
    `ASSERT(IntrStateSet_A, event_i && !sw_clear_i |=> intr_state[i], clk_i, !rst_ni)

    // Sticky until written. This is what makes it an Event interrupt rather than a Status one.
    `ASSERT(IntrStateSticky_A, intr_state[i] && !sw_clear_i |=> intr_state[i], clk_i, !rst_ni)

    // A write of one clears, when nothing is setting the bit in the same cycle.
    `ASSERT(IntrStateClear_A, sw_clear_i && !event_i |=> !intr_state[i], clk_i, !rst_ni)

    // And nothing else sets it. Without this the three above would pass on a device that set
    // every bit permanently.
    `ASSERT(IntrStateNoSpurious_A, !intr_state[i] && !event_i |=> !intr_state[i], clk_i, !rst_ni)

    // The pin is the state gated by the enable, one flop behind, because prim_intr_hw is
    // instantiated with FlopOutput.
    `ASSERT(IntrPin_A, intr_o[i] == $past(intr_state[i] & intr_enable[i]), clk_i, !rst_ni)
  end : gen_intr_assert

endmodule
