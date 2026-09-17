// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the wakeup test: several rounds, no reset.
class pwrmgr_rst_safe_wakeup_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_wakeup_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[2 : 5]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_wakeup_test_seq_parameters


// Wakeups with everything software controls randomized: which sources are enabled, whether the
// device records why it woke, whether the interrupt is enabled, and whether last round's record is
// left in place. The smoke enables everything and clears between rounds, so it never sees a wakeup
// raised but not enabled, or reasons accumulating.
class pwrmgr_rst_safe_wakeup_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_wakeup_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_wakeup_round();
  extern protected task clear_recorded_wake_info();
endclass : pwrmgr_rst_safe_wakeup_vseq


function pwrmgr_rst_safe_wakeup_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_wakeup_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_wakeup_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf(
              "Wakeup round %0d of %0d: raised 0x%0x, enabled 0x%0x, capture %0sabled, %0s prior",
              i + 1, test_params.num_trans, config_params.wakeups, config_params.wakeups_en,
              config_params.disable_wakeup_capture ? "dis" : "en",
              config_params.keep_prior_wake_info ? "keeping" : "clearing"), UVM_MEDIUM)
    run_wakeup_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_wakeup_vseq::run_wakeup_round();
  uvm_reg_data_t rd_value;

  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  csr_wr(.ptr(ral.intr_enable.wakeup), .value(config_params.en_intr));

  // Either leave what the previous round recorded in place, so the reasons accumulate, or take
  // it away and start from nothing.
  if (!config_params.keep_prior_wake_info) clear_recorded_wake_info();
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(config_params.disable_wakeup_capture));

  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_processor_sleeping(1'b1);
  wait_for_low_power_entry();

  discard_stale_observations();
  set_wakeups(config_params.wakeups);
  wait_for_device_active();

  // Read while the wakeup is still raised. The status follows the sources that are asserted
  // and enabled, so it reads differently once they are taken away, which the end of this round
  // does deliberately.
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));

  // The interrupt is recorded whether or not software enabled it, so it is read either way.
  if (config_params.en_intr) wait_for_wakeup_interrupt();
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  set_wakeups('0);
  set_processor_sleeping(1'b0);
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
endtask : run_wakeup_round


// Capture has to be disabled for the recorded reasons to be cleared, so the setting is put back
// afterwards by the caller.
task pwrmgr_rst_safe_wakeup_vseq::clear_recorded_wake_info();
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b1));
  csr_wr(.ptr(ral.wake_info), .value('1));
endtask : clear_recorded_wake_info
