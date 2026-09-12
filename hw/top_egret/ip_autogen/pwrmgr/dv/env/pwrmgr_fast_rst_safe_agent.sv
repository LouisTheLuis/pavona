// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The agent for the fast side of the device. Its reset domain is the fast domain's own reset,
// which is a leaf of the power-on reset and is released by the always-on agent once the clock
// is back. It is deliberately not the lc reset: this agent grants that one, and a component
// cannot be reset by something it drives.
class pwrmgr_fast_rst_safe_agent extends dv_rst_safe_base_agent #(
    .CFG_T      (pwrmgr_fast_agent_cfg),
    .DRIVER_T   (pwrmgr_fast_rst_safe_driver),
    .SEQUENCER_T(pwrmgr_fast_sequencer),
    .MONITOR_T  (pwrmgr_fast_rst_safe_monitor),
    .COV_T      (dv_base_agent_cov)
  );

  `uvm_component_utils(pwrmgr_fast_rst_safe_agent)
  `uvm_component_new
endclass : pwrmgr_fast_rst_safe_agent
