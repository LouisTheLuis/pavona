// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Carries one item to the fast agent. See pwrmgr_aon_seq for why this is a sequence.

class pwrmgr_fast_seq extends dv_base_seq #(
    .REQ        (pwrmgr_fast_item),
    .CFG_T      (pwrmgr_fast_agent_cfg),
    .SEQUENCER_T(pwrmgr_fast_sequencer)
  );

  bit core_sleeping_value;

  `uvm_object_utils(pwrmgr_fast_seq)

  function new(string name = "");
    super.new(name);
  endfunction : new

  virtual task body();
    req = pwrmgr_fast_item::type_id::create("req");
    start_item(req);
    `DV_CHECK_RANDOMIZE_WITH_FATAL(req, core_sleeping == core_sleeping_value;)
    finish_item(req);
  endtask : body
endclass : pwrmgr_fast_seq
