// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Configuration for the agent that models the blocks the device talks to on its fast clock:
// rstmgr granting the resets it asks for, clkmgr reporting the clocks it enables, and otp and
// lifecycle answering their initialization requests.
class pwrmgr_fast_agent_cfg extends dv_base_agent_cfg;

  // The device interface. The driver writes the interface and the monitor samples it.
  virtual pwrmgr_if vif;

  // The resets this agent grants. rstmgr turns the device's request into these, so they follow
  // what the driver answers rather than anything a test applies.
  virtual clk_rst_if lc_clk_rst_vif;
  virtual clk_rst_if esc_clk_rst_vif;

  // The escalation pair. The shared escalation agent's sender driver is unimplemented by
  // design, so a sequence can only reach this interface by writing it directly, which the
  // reset-safe path does not allow. Modelling the alert handler here keeps escalation as
  // stimulus carried by an item and keeps the pin in a driver.
  virtual alert_esc_if esc_vif;

  // Reports the registers the device writes itself, at the moment it commits them.

  // How long each peer takes to answer, in fast clock cycles. Randomized once when the
  // configuration is built and then left alone, so that answers already in flight keep the
  // order their requests arrived in.
  rand int unsigned cycles_before_rst_lc_src;
  rand int unsigned cycles_before_rst_sys_src;
  rand int unsigned cycles_before_clk_status;
  rand int unsigned cycles_before_otp_done;
  rand int unsigned cycles_before_lc_done;

  // How long the rom check takes before it reports a result. The device cannot reach active
  // until it does, so this is the boot time the testbench presents.
  rand int unsigned cycles_before_rom_done;

  constraint cycles_before_rst_lc_src_c {cycles_before_rst_lc_src inside {[0 : 4]};}
  constraint cycles_before_rst_sys_src_c {cycles_before_rst_sys_src inside {[0 : 4]};}
  constraint cycles_before_clk_status_c {cycles_before_clk_status inside {[0 : 4]};}
  constraint cycles_before_otp_done_c {cycles_before_otp_done inside {[0 : 4]};}
  constraint cycles_before_lc_done_c {cycles_before_lc_done inside {[0 : 4]};}
  constraint cycles_before_rom_done_c {cycles_before_rom_done inside {[2 : 20]};}

  `uvm_object_utils_begin(pwrmgr_fast_agent_cfg)
    `uvm_field_int(cycles_before_rst_lc_src, UVM_DEFAULT)
    `uvm_field_int(cycles_before_rst_sys_src, UVM_DEFAULT)
    `uvm_field_int(cycles_before_clk_status, UVM_DEFAULT)
    `uvm_field_int(cycles_before_otp_done, UVM_DEFAULT)
    `uvm_field_int(cycles_before_lc_done, UVM_DEFAULT)
    `uvm_field_int(cycles_before_rom_done, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_fast_agent_cfg
