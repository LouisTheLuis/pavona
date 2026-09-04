// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe agent owning both device facing pin interfaces of the block: the bidirectional
// GPIO net and the strap trigger and broadcast. One agent covers both because they share a
// reset domain and a clock, and because the strap sample is taken from the same input path
// the GPIO pins feed.
class gpio_rst_safe_agent extends dv_rst_safe_base_agent #(
    .CFG_T       (gpio_agent_cfg),
    .DRIVER_T    (gpio_rst_safe_driver),
    .SEQUENCER_T (gpio_sequencer),
    .MONITOR_T   (gpio_rst_safe_monitor),
    .COV_T       (dv_base_agent_cov)
  );
  `uvm_component_utils(gpio_rst_safe_agent)
  `uvm_component_new

  extern function void build_phase(uvm_phase phase);
endclass : gpio_rst_safe_agent


function void gpio_rst_safe_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  if (cfg.gpio_vif == null) begin
    `uvm_fatal(`gfn, "cfg.gpio_vif is null; the environment must set it before build")
  end
  if (cfg.straps_vif_inst == null) begin
    `uvm_fatal(`gfn, "cfg.straps_vif_inst is null; the environment must set it before build")
  end
  if (cfg.intr_vif_inst == null) begin
    `uvm_fatal(`gfn, "cfg.intr_vif_inst is null; the environment must set it before build")
  end
endfunction : build_phase
