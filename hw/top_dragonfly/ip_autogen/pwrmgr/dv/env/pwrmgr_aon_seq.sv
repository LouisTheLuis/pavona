// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Carries one item to the always-on agent.
//
// The virtual sequence could hand an item straight to the agent's sequencer, but then it is the
// virtual sequence that sits in that sequencer's queue, and the agent kills everything in that
// queue when reset asserts. That would take the reset loop down with it, and the test would end
// early and report success because nothing had gone wrong, only stopped. Starting a sequence
// keeps the kill where it belongs: uvm_sequence_base::start() runs a body in its own process,
// so killing the child returns control to the caller.

class pwrmgr_aon_seq extends dv_base_seq #(
    .REQ        (pwrmgr_aon_item),
    .CFG_T      (pwrmgr_aon_agent_cfg),
    .SEQUENCER_T(pwrmgr_aon_sequencer)
  );

  // What to deliver. Built and randomized by the caller, which is the only place that knows which
  // fields the request is about and what the rest should be left at.
  pwrmgr_aon_item item;

  // Which peripherals are asking for a reset. The item's own constraint keeps these clear, so a
  // test that wants them has to say so.
  resets_t rstreqs_value;

  // A glitch on the main power supply, and how long it lasts in slow clock cycles.
  bit          escalation_reset_value;
  bit          esc_clk_stopped_value;
  int unsigned esc_clk_stopped_cycles_value = 0;
  bit          esc_rst_asserted_value;

  bit power_glitch_value;
  int unsigned glitch_width_slow_clks_value = 1;

  // What rstmgr is forwarding from software. Only the true encoding requests a reset; the
  // others are the interesting negative cases and have to be reachable.
  bit [MUBI4W-1:0] sw_rst_req_value = MuBi4False;

  // Cycles the driver waits before applying, so two inputs can be placed relative to one
  // another without a delay in the sequence.
  int unsigned apply_delay_cycles = 0;

  `uvm_object_utils(pwrmgr_aon_seq)

  function new(string name = "");
    super.new(name);
  endfunction : new

  virtual task body();
    `DV_CHECK_FATAL(item != null, "Started without an item to carry")
    start_item(item);
    finish_item(item);
  endtask : body
endclass : pwrmgr_aon_seq
