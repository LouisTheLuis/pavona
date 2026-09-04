// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Build time configuration for the reset-safe GPIO agent.
//
// This carries interface handles and immutable build-time policy only. Observed pin state,
// strap results and interrupt state travel as monitor transactions, never through here.
class ${module_instance_name}_agent_cfg extends dv_base_agent_cfg;

  // The bidirectional GPIO pin net. The driver owns pins_o, pins_oe, pins_pu and pins_pd on
  // this interface; nothing else may write them.
  gpio_vif gpio_vif;

  // The strap trigger and the sampled strap broadcast. The driver owns strap_en; the monitor
  // observes sampled_straps.
  straps_vif straps_vif_inst;

  // The interrupt output pins, observed only. This handle is copied from the environment
  // configuration, which owns the interface: the common CIP base sequences also sample it for
  // their own interrupt checks, so the agent is one reader among several rather than the
  // owner. The agent observes it here so that this block's scoreboard can consume interrupt
  // state as a transaction with the same reset lifecycle and the same epoch cycle count as
  // the pin observations it has to be lined up against.
  intr_vif intr_vif_inst;

  // Passive observation of the device's hardware register commits, bound into the device.
  // Read only, and its values must be checked against a prediction before anything is
  // predicted from them.
  ${module_instance_name}_probe_vif probe_vif_inst;

  // Elaboration of the device this agent is connected to, copied from the environment
  // configuration before the run phase. The monitor does not change what it publishes based
  // on these, but a consumer needs them to interpret the observations, and keeping one copy
  // here means the agent never reaches back into the environment configuration.
  bit gpio_async_on;
  bit gpio_as_hw_straps_en;

  // Board topology: the weak pulls present on the net when nothing is driving it. Build-time
  // rather than stimulus, because a board does not grow and lose its pull resistors during a
  // test, and because the driver has to be able to establish them at power-on reset before
  // any sequence exists to ask for them. Without a pull the net floats out of every reset and
  // the undriven value propagates through the filter into DATA_IN and the interrupt logic.
  bit [NUM_GPIOS-1:0] default_pullup_en;
  bit [NUM_GPIOS-1:0] default_pulldown_en;

  `uvm_object_utils_begin(${module_instance_name}_agent_cfg)
    `uvm_field_int(gpio_async_on,        UVM_DEFAULT)
    `uvm_field_int(gpio_as_hw_straps_en, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : ${module_instance_name}_agent_cfg
