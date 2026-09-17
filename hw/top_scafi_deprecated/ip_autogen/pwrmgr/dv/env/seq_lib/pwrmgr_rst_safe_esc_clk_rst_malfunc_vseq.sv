// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the escalation clock and reset malfunction test.
class pwrmgr_rst_safe_esc_clk_rst_malfunc_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_esc_clk_rst_malfunc_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[1 : 3]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_esc_clk_rst_malfunc_test_seq_parameters


// The escalation side failing outright, either because its clock has gone or because it is held in
// reset. The device notices through the same timeout either way and resets itself, raising a fatal
// alert.
//
// The difference from the timeout test is what is broken rather than for how long: here it does not
// come back on its own at all.
class pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq)

  extern function new(string name = "");
  extern virtual task pre_start();
  extern virtual task main_thread();
  extern protected task run_malfunction_round(bit by_reset);
endclass : pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq


function pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_esc_clk_rst_malfunc_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    run_malfunction_round(.by_reset(config_params.esc_malfunction_by_reset));
  end
endtask : main_thread


task pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq::run_malfunction_round(bit by_reset);
  uvm_reg_data_t rd_value;

  `uvm_info(`gfn, $sformatf("Breaking the escalation side by %0s", by_reset ? "reset" : "clock"),
            UVM_MEDIUM)

  discard_stale_observations();
    set_escalation_malfunction(.clk_stopped(!by_reset), .rst_asserted(by_reset));

  // Stopping the processor fetching is the device saying it has noticed. What was broken is
  // mended there, so the device finds a working escalation side when it comes back rather than
  // the same fault and another reset.
  wait_for_low_power_entry_started();
  set_escalation_malfunction(.clk_stopped(1'b0), .rst_asserted(1'b0));

  wait_for_device_active();
  csr_rd(.ptr(ral.fault_status), .value(rd_value));
endtask : run_malfunction_round


// The device raises its fatal alert for this on purpose, so the blanket check for an
// unexplained alert is stood down. The scoreboard still checks that each alert is accounted
// for by something it observed.
task pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq::pre_start();
  expect_fatal_alerts = 1'b1;
  super.pre_start();
endtask : pre_start
