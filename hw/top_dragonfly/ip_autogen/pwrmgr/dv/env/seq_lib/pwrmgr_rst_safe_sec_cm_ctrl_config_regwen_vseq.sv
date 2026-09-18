// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the control write enable test: several rounds, no reset.
class pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[2 : 5]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_test_seq_parameters


// The device locks its control register while it is acting on a low power transition, so software
// cannot change the terms of one already under way. Each round asks for a transition, writes while
// it is locked, and checks the write did not take.
class pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_regwen_round();
endclass : pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq


function pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    run_regwen_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq::run_regwen_round();
  uvm_reg_data_t rd_value;

  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));

  // The lock is read over the bus while the device is down, so the transition has to be one the bus
  // survives: the main power domain stays up and the io clock keeps running, and neither is the
  // default.
  //
  // They are pinned rather than skipped when they do not hold, which is what the legacy sequence
  // does. A round that cannot reach the register checks nothing. What `main_pd_n` does to a
  // transition is covered where it is the subject.
  stage_clock_enables();
  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(1'b1);
  ral.control.io_clk_en.set(1'b1);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_processor_sleeping(1'b1);
  wait_for_low_power_entry();

  // The device has the transition in hand, so the lock is set and the control register keeps
  // what it already had.
  csr_rd(.ptr(ral.ctrl_cfg_regwen), .value(rd_value));
  csr_wr(.ptr(ral.control), .value('0));
  csr_rd(.ptr(ral.control), .value(rd_value));

  discard_stale_observations();
  set_wakeups(config_params.wakeups);
  wait_for_device_active();

  // Read so the wakeup this round raised is checked. The checker predicts the status from the
  // sources and enables it was given, and a read is what puts that prediction against the device.
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));

  // Back from the transition, the lock is clear and the register takes a write again.
  csr_rd(.ptr(ral.ctrl_cfg_regwen), .value(rd_value));
  stage_clock_enables();
  ral.control.low_power_hint.set(1'b0);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  csr_rd(.ptr(ral.control), .value(rd_value));

  set_wakeups('0);
  set_processor_sleeping(1'b0);
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
endtask : run_regwen_round
