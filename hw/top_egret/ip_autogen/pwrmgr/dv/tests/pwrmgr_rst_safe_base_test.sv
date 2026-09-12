// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test for the reset-safe environment. The common CIP base creates the configuration and the
// environment and runs the sequence named by the plusarg, so there is nothing to add here.
class pwrmgr_rst_safe_base_test extends cip_base_test #(
    .CFG_T(pwrmgr_env_cfg),
    .ENV_T(pwrmgr_rst_safe_env)
  );

  `uvm_component_utils(pwrmgr_rst_safe_base_test)
  `uvm_component_new
endclass : pwrmgr_rst_safe_base_test
