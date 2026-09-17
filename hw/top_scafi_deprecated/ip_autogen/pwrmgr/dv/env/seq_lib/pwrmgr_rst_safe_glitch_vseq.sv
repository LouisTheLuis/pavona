// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the glitch test: a few rounds, no reset from the framework. The glitch is the
// reset.
class pwrmgr_rst_safe_glitch_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_glitch_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[1 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_glitch_test_seq_parameters


// A dip on the main power supply, which the device treats as a reset in its own right and reports
// as a fault rather than an ordinary reset request. The width is stimulus, not a delay: the driver
// applies it on the slow clock the supply belongs to.
class pwrmgr_rst_safe_glitch_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_glitch_vseq)

  extern function new(string name = "");
  extern virtual task pre_start();
  extern virtual task main_thread();
  extern protected task run_glitch_round();
endclass : pwrmgr_rst_safe_glitch_vseq


function pwrmgr_rst_safe_glitch_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_glitch_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_glitch_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf("Glitch round %0d of %0d: %0d slow clocks wide", i + 1,
                              test_params.num_trans, config_params.glitch_width_slow_clks),
              UVM_MEDIUM)
    run_glitch_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_glitch_vseq::run_glitch_round();
  uvm_reg_data_t rd_value;

  discard_stale_observations();
  send_power_glitch(config_params.glitch_width_slow_clks);

  // The device goes away and comes back. Its saying the processor may run again is what marks
  // the end, and the boundary the checker compares at.
  wait_for_device_active();

  // The glitch is a fault rather than a reset anything asked for, so it is reported separately
  // and nothing should have been recorded about a wakeup.
  csr_rd(.ptr(ral.fault_status), .value(rd_value));
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));
endtask : run_glitch_round


// The device raises its fatal alert for this on purpose, so the blanket check for an
// unexplained alert is stood down. The scoreboard still checks that each alert is accounted
// for by something it observed.
task pwrmgr_rst_safe_glitch_vseq::pre_start();
  expect_fatal_alerts = 1'b1;
  super.pre_start();
endtask : pre_start
