// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class keymgr_dpe_base_test extends cip_base_test #(
    .CFG_T(keymgr_dpe_env_cfg),
    .ENV_T(keymgr_dpe_env)
  );

  `uvm_component_utils(keymgr_dpe_base_test)
  `uvm_component_new

  // the base class dv_base_test creates the following instances:
  // keymgr_dpe_env_cfg: cfg
  // keymgr_dpe_env:     env

  // the base class also looks up UVM_TEST_SEQ plusarg to create and run that seq in
  // the run_phase; as such, nothing more needs to be done

  // An operation costs a roughly fixed number of clock cycles, so what the test needs is a budget
  // in cycles. `test_timeout_ns` is spent in simulated time and the clock frequency is randomized
  // over a twenty to one range, so a constant sized for the fastest clock ends a slow run with its
  // sequence still making progress. This is the count that constant bought at the top of the range.
  static const longint unsigned TestTimeoutCycles = 20_000_000;

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    test_timeout_ns = (TestTimeoutCycles * 1000) / cfg.clk_freq_mhz;
    // The base class applies a `+test_timeout_ns` plusarg after this, so a run option still wins.
    super.end_of_elaboration_phase(phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // keymgr requests entropy periodically, if seq is done, don't need to add any delay due to
    // activity from EDN interface which may prevent sim from finishing
    drain_time_ns = 0;
    super.run_phase(phase);
  endtask
endclass : keymgr_dpe_base_test
