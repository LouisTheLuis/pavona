// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_virtual_sequencer extends cip_base_virtual_sequencer #(.CFG_T(i2c_env_cfg),
                                                                 .COV_T(i2c_env_cov));
  i2c_sequencer    i2c_sequencer_h;

  `uvm_component_utils(i2c_virtual_sequencer)
  `uvm_component_new

  virtual function void handle_reset_assertion();
    `uvm_info(`gfn, "Reset assertion: reset-safe agents own sequencer cleanup", UVM_LOW)

    // clk_rst_sequencer_h is free-running and must not be stopped. The reset-safe
    // TL, delay and I2C agents stop their own sequencers when their reset monitors
    // observe assertion. Alert response traffic must also remain alive through reset.
    // TODO(rst_safe): Audit this hook whenever a non-reset-safe active agent is added
    // to the I2C environment; only such a sequencer should be stopped here.
  endfunction : handle_reset_assertion

endclass : i2c_virtual_sequencer
