// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_rst_safe_base_test extends cip_base_test #(
    .ENV_T(i2c_rst_safe_env),
    .CFG_T(i2c_env_cfg)
);
  `uvm_component_utils(i2c_rst_safe_base_test)
  `uvm_component_new

  virtual function void add_message_demotes(dv_report_catcher catcher);
    string msg;

    super.add_message_demotes(catcher);

    // A finite reset-safe smoke epoch can complete before a deliberately long
    // randomized reset delay. This is expected for these two focused smoke
    // sequences and does not indicate failed reset cleanup. Keep the demotion
    // scoped to their exact sequence instance IDs so all other reset, stress,
    // scoreboard and assertion diagnostics retain their original severity.
    msg = ".*Reset Testing Enabled and main_thread.*finished before reset_trigger_thread.*";
    catcher.add_change_sev(
        "uvm_test_top.env.virtual_sequencer.i2c_host_rst_safe_smoke_with_rand_reset_vseq",
        msg, UVM_INFO);
    catcher.add_change_sev(
        "uvm_test_top.env.virtual_sequencer.i2c_target_rst_safe_smoke_with_rand_reset_vseq",
        msg, UVM_INFO);
  endfunction : add_message_demotes

  virtual function void build_phase(uvm_phase phase);
    if_mode_e mode = Device;
    test_timeout_ns = 10_000_000_000;  // Conservative bring-up limit; tune from regressions.
    super.build_phase(phase);

    // The parent build creates cfg and the child environment is built only after
    // this function returns. Fix this build-time policy here so reset-safe
    // prediction and stimulus never exchange runtime state through cfg.
    cfg.legacy_runtime_state_compat = 1'b0;
    cfg.m_i2c_agent_cfg.use_legacy_got_stop_handshake = 1'b0;

    `DV_GET_ENUM_PLUSARG(if_mode_e, mode, i2c_agent_mode)
    `uvm_info(`gfn, $sformatf("set i2c reset-safe agent mode to %s", mode.name), UVM_MEDIUM)
    cfg.m_i2c_agent_cfg.if_mode = mode;

    // Static agent timing paired with the deterministic smoke timing CSRs. This
    // is build-time configuration, not runtime state exchanged with a sequence.
    cfg.m_i2c_agent_cfg.timing_cfg.tSetupStart = 7;
    cfg.m_i2c_agent_cfg.timing_cfg.tHoldStart = 7;
    cfg.m_i2c_agent_cfg.timing_cfg.tClockStart = 2;
    cfg.m_i2c_agent_cfg.timing_cfg.tClockLow = 3;
    cfg.m_i2c_agent_cfg.timing_cfg.tSetupBit = 4;
    cfg.m_i2c_agent_cfg.timing_cfg.tClockPulse = 14;
    cfg.m_i2c_agent_cfg.timing_cfg.tHoldBit = 4;
    cfg.m_i2c_agent_cfg.timing_cfg.tClockStop = 10;
    cfg.m_i2c_agent_cfg.timing_cfg.tSetupStop = 7;
    cfg.m_i2c_agent_cfg.timing_cfg.tHoldStop = 5;
    cfg.m_i2c_agent_cfg.timing_cfg.enbTimeOut = 1'b0;
    cfg.m_i2c_agent_cfg.timing_cfg.tSdaUnstable = 0;
    cfg.m_i2c_agent_cfg.timing_cfg.tSdaInterference = 0;
    cfg.m_i2c_agent_cfg.timing_cfg.tSclInterference = 0;
  endfunction : build_phase
endclass : i2c_rst_safe_base_test
