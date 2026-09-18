// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Coverage for the reset-safe environment.
//
// Holds the groups the reset-safe scoreboard samples, which it does from what the checker has
// already predicted and compared. The normal environment keeps pwrmgr_env_cov and samples the same
// groups from signal activity, so the two reports stay separable and the normal class can retire
// with the environment that uses it.
//
// reset_wakeup_distance_cg is left to pwrmgr_env_cov: the reset-safe scoreboard has no checked
// event that measures the distance it records.
class pwrmgr_rst_safe_env_cov extends cip_base_env_cov #(.CFG_T(pwrmgr_env_cfg));
  `uvm_component_utils(pwrmgr_rst_safe_env_cov)

  pwrmgr_wakeup_ctrl_cg_wrap wakeup_ctrl_cg_wrap[pwrmgr_reg_pkg::NumWkups];
  pwrmgr_wakeup_intr_cg_wrap wakeup_intr_cg_wrap[pwrmgr_reg_pkg::NumWkups];

  pwrmgr_control_cg control_cg;
  pwrmgr_hw_reset_0_cg hw_reset_0_cg;
  pwrmgr_hw_reset_1_cg hw_reset_1_cg;
  pwrmgr_rstmgr_sw_reset_cg rstmgr_sw_reset_cg;
  pwrmgr_main_power_reset_cg main_power_reset_cg;
  pwrmgr_esc_reset_cg esc_reset_cg;
  pwrmgr_rom_active_blockers_cg rom_active_blockers_cg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    foreach (wakeup_ctrl_cg_wrap[i]) begin
      pwrmgr_env_pkg::wakeup_e wakeup = pwrmgr_env_pkg::wakeup_e'(i);
      wakeup_ctrl_cg_wrap[i] = new({wakeup.name, "_ctrl_cg"});
      wakeup_intr_cg_wrap[i] = new({wakeup.name, "_intr_cg"});
    end
    control_cg = new();
    hw_reset_0_cg = new();
    hw_reset_1_cg = new();
    rstmgr_sw_reset_cg = new();
    main_power_reset_cg = new();
    esc_reset_cg = new();
    rom_active_blockers_cg = new();
  endfunction : new
endclass : pwrmgr_rst_safe_env_cov
