// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Carries one item to the fast agent. See pwrmgr_aon_seq for why this is a sequence.

class pwrmgr_fast_seq extends dv_base_seq #(
    .REQ        (pwrmgr_fast_item),
    .CFG_T      (pwrmgr_fast_agent_cfg),
    .SEQUENCER_T(pwrmgr_fast_sequencer)
  );

  // What to deliver. Built and randomized by the caller, for the same reason as on the
  // always-on side.
  pwrmgr_fast_item item;

  `uvm_object_utils(pwrmgr_fast_seq)

  function new(string name = "");
    super.new(name);
  endfunction : new

  virtual task body();
    `DV_CHECK_FATAL(item != null, "Started without an item to carry")
    start_item(item);
    finish_item(item);
  endtask : body
endclass : pwrmgr_fast_seq
