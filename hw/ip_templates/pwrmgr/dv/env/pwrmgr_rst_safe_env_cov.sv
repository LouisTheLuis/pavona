// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Coverage for the reset-safe environment.
//
// Kept separate from pwrmgr_env_cov so that the groups the normal environment samples from raw
// signal activity do not appear in a reset-safe report. The groups here are added once the
// checker accepts and compares the result they describe, so that a bin records something that
// was checked rather than something that merely happened.
class pwrmgr_rst_safe_env_cov extends cip_base_env_cov #(.CFG_T(pwrmgr_env_cfg));

  `uvm_component_utils(pwrmgr_rst_safe_env_cov)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new
endclass : pwrmgr_rst_safe_env_cov
