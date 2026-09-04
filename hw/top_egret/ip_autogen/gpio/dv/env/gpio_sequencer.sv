// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Sequencer for the reset-safe GPIO agent. It is a named class rather than an inline
// parameterization so that the factory has something to register and an override has
// something to target.
//
// There is no monitor fed FIFO here. Pin and strap observations go to the scoreboard and,
// where a sequence needs to synchronize on one, to a FIFO on the virtual sequencer, so that
// a stimulus consumer cannot take an item the checker was owed.
class gpio_sequencer extends dv_base_sequencer #(
    .ITEM_T(gpio_seq_item),
    .CFG_T (gpio_agent_cfg)
  );
  `uvm_component_utils(gpio_sequencer)
  `uvm_component_new
endclass : gpio_sequencer
