// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Virtual sequencer for the reset-safe environment.
//
// It carries the monitor fed FIFOs that stimulus needs in order to synchronize on something
// the device did, so that no reset-safe sequence has to look at a pin to find out. The
// scoreboard has its own separate connections to the same monitor ports, so a sequence
// draining one of these FIFOs cannot take an observation the checker was owed.
class gpio_rst_safe_virtual_sequencer extends cip_base_virtual_sequencer #(
    .CFG_T(gpio_env_cfg),
    .COV_T(gpio_rst_safe_env_cov)
  );
  `uvm_component_utils(gpio_rst_safe_virtual_sequencer)

  // Sequencer for the GPIO pin and strap agent.
  gpio_sequencer gpio_sequencer_h;

  // Interrupt pin observations, for a sequence that needs to wait for an interrupt rather
  // than poll INTR_STATE over the bus.
  uvm_tlm_analysis_fifo #(gpio_intr_item) intr_event_fifo;

  // Strap sample observations, for the directed strap sequence.
  uvm_tlm_analysis_fifo #(gpio_straps_item) straps_event_fifo;

  extern function new(string name = "", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void handle_reset_assertion();
endclass : gpio_rst_safe_virtual_sequencer


function gpio_rst_safe_virtual_sequencer::new(string name = "",
                                                                 uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void gpio_rst_safe_virtual_sequencer::build_phase(uvm_phase phase);
  super.build_phase(phase);
  intr_event_fifo   = new("intr_event_fifo", this);
  straps_event_fifo = new("straps_event_fifo", this);
endfunction : build_phase


function void gpio_rst_safe_virtual_sequencer::handle_reset_assertion();
  // Both FIFOs hold observations that belong to the epoch that just ended. A sequence
  // starting in the next epoch must not be able to take one and act on it.
  //
  // No sequencer is stopped here. clk_rst_sequencer_h is driving the reset and must stay
  // alive; the reset-safe TL, delay and GPIO agents stop their own sequencers when their
  // reset monitors see the assertion. Any future active agent that is not built on
  // dv_rst_safe_base_agent would have to be stopped from this hook.
  intr_event_fifo.flush();
  straps_event_fifo.flush();
endfunction : handle_reset_assertion
