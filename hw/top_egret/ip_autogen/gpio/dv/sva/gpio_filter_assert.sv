// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The noise filter's contract as this block states it: once the filter is enabled, an input
// value must be stable for the filter window before it reaches DATA_IN.
//
// Written against the block's own signals, the pin and the filtered input, rather than
// against anything inside prim_filter_ctr. The primitive's internals are not this block's to
// depend on, and a property bound by module name would also attach to every instance of that
// primitive in whatever design the file is elaborated into.
//
// This assumes the input synchronizer is not instantiated, which is how the testbench
// elaborates the block. With it the filter would see the pin two flops later, and its own
// randomization is driven by a $urandom that does not replay from the seed.
module gpio_filter_assert #(
  parameter int unsigned NumIOs   = 32,
  parameter int unsigned CntWidth = 4
) (
  input logic              clk_i,
  input logic              rst_ni,
  input logic [NumIOs-1:0] raw_in,
  input logic [NumIOs-1:0] filter_en,
  input logic [NumIOs-1:0] data_in
);

  // Cycles an input must hold before the filter passes it.
  localparam int unsigned Thresh = (1 << CntWidth) - 1;

  for (genvar i = 0; i < NumIOs; i++) begin : gen_filter_assert
    // A pin nothing is driving has no value to check against. That is a legal state on a
    // board with no weak pulls, which the testbench models, so every property below is
    // qualified on the pin being resolved rather than being allowed to fail on it.
    logic known_i;
    assign known_i = !$isunknown(raw_in[i]) && !$isunknown(data_in[i]);

    // Disabled, the filter is transparent and the pin reaches DATA_IN in the same cycle.
    `ASSERT(FilterTransparent_A,
            known_i && !filter_en[i] |-> data_in[i] === raw_in[i], clk_i, !rst_ni)

    // Enabled, the filtered input cannot move twice inside the window. This is the property
    // the filter exists for, and it is what a glitch getting through would break. Stated as an
    // interval so that it does not depend on the phase of the counter inside the primitive.
    //
    // The obligation is released if the filter is turned off inside the window, because the
    // output then switches to following the pin directly and may move on any cycle. Checking
    // the enable only at the start would fail on a test that reprograms the filter.
    `ASSERT(FilterMinInterval_A,
            known_i && filter_en[i] && $stable(filter_en[i]) && $changed(data_in[i])
            |=> (!$changed(data_in[i]) || !filter_en[i])[*Thresh],
            clk_i, !rst_ni)

    // And when it moves, it moves to a value the pin actually presented, one flop earlier.
    `ASSERT(FilterTracksInput_A,
            known_i && !$isunknown($past(raw_in[i])) &&
            filter_en[i] && $stable(filter_en[i]) && $changed(data_in[i])
            |-> data_in[i] === $past(raw_in[i]), clk_i, !rst_ni)
  end : gen_filter_assert

endmodule
