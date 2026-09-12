// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The agent for the always-on side of the device: the AST power and clock handshake, the
// peripheral wakeup and reset requests, and the software reset request.
//
// Its reset domain is the power-on reset, the only reset a test applies, so it is alive across
// every reset it has to recover from and across the resets it restores for the other domains.
class pwrmgr_aon_rst_safe_agent extends dv_rst_safe_base_agent #(
    .CFG_T      (pwrmgr_aon_agent_cfg),
    .DRIVER_T   (pwrmgr_aon_rst_safe_driver),
    .SEQUENCER_T(pwrmgr_aon_sequencer),
    .MONITOR_T  (pwrmgr_aon_rst_safe_monitor),
    .COV_T      (dv_base_agent_cov)
  );

  `uvm_component_utils(pwrmgr_aon_rst_safe_agent)
  `uvm_component_new
endclass : pwrmgr_aon_rst_safe_agent
