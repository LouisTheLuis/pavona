// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Base test for the reset-safe path. Separate from gpio_base_test so that the
// legacy tests keep the legacy environment and neither has to know about the other.
//
// It does not drive the strap interface. The legacy base test does, from reset_phase() under
// a raised objection; here strap_en belongs to the agent driver.
class gpio_rst_safe_base_test extends cip_base_test #(
    .ENV_T(gpio_rst_safe_env),
    .CFG_T(gpio_env_cfg)
  );
  `uvm_component_utils(gpio_rst_safe_base_test)

  extern function new(string name = "", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
endclass : gpio_rst_safe_base_test


function gpio_rst_safe_base_test::new(string name = "",
                                                         uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void gpio_rst_safe_base_test::build_phase(uvm_phase phase);
  test_timeout_ns = 1_000_000_000; // 1s
  super.build_phase(phase);
endfunction : build_phase
