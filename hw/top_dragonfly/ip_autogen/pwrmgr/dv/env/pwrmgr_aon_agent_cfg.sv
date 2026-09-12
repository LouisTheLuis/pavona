// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Configuration for the agent that models the always-on side of the device: the AST power and
// clock answers, the peripheral wakeup and reset requests, and the software reset request.
class pwrmgr_aon_agent_cfg extends dv_base_agent_cfg;

  // The device interface. The driver writes the interface and the monitor samples it.
  virtual pwrmgr_if vif;

  // The clocks and resets this agent restores. The device asks AST for its clocks, so they run
  // only while this agent answers, and the fast domain cannot leave reset until its clock is
  // back. See the release path in the driver.
  virtual clk_rst_if fast_clk_rst_vif;
  virtual clk_rst_if lc_clk_rst_vif;
  virtual clk_rst_if esc_clk_rst_vif;

  // How long AST takes to answer, in slow clock cycles. These are randomized once when the
  // configuration is built and then left alone, because a response already in flight must not
  // have its delay changed underneath it: two requests close together would otherwise be
  // answered out of order.
  rand int unsigned cycles_before_main_pok;
  rand int unsigned cycles_before_clk_val;

  constraint cycles_before_main_pok_c {cycles_before_main_pok inside {[2 : 12]};}
  constraint cycles_before_clk_val_c {cycles_before_clk_val inside {[1 : 12]};}

  `uvm_object_utils_begin(pwrmgr_aon_agent_cfg)
    `uvm_field_int(cycles_before_main_pok, UVM_DEFAULT)
    `uvm_field_int(cycles_before_clk_val, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_aon_agent_cfg
