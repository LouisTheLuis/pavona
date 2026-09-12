// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Virtual sequencer for the reset-safe environment.
//
// It adds the two block sequencers and one fifo. The clock/reset and delay sequencer handles
// come from the common base and are not repeated here.
class pwrmgr_rst_safe_virtual_sequencer extends cip_base_virtual_sequencer #(
    .CFG_T(pwrmgr_env_cfg),
    .COV_T(pwrmgr_rst_safe_env_cov)
  );

  `uvm_component_utils(pwrmgr_rst_safe_virtual_sequencer)

  pwrmgr_aon_sequencer  aon_sequencer_h;
  pwrmgr_fast_sequencer fast_sequencer_h;

  // Fast side observations, so a sequence can wait for something the device announced rather
  // than watch a pin. The device reporting that the processor may run is what gates the first
  // register access after a reset.
  uvm_tlm_analysis_fifo #(pwrmgr_active_item) active_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)   low_power_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)   intr_fifo;

  extern function new(string name = "", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void handle_reset_assertion();
endclass : pwrmgr_rst_safe_virtual_sequencer


function pwrmgr_rst_safe_virtual_sequencer::new(string name = "", uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void pwrmgr_rst_safe_virtual_sequencer::build_phase(uvm_phase phase);
  super.build_phase(phase);
  active_fifo    = new("active_fifo", this);
  low_power_fifo = new("low_power_fifo", this);
  intr_fifo      = new("intr_fifo", this);
endfunction : build_phase


function void pwrmgr_rst_safe_virtual_sequencer::handle_reset_assertion();
  // Anything observed before the reset describes a device that no longer exists.
  active_fifo.flush();
  low_power_fifo.flush();
  intr_fifo.flush();
endfunction : handle_reset_assertion
