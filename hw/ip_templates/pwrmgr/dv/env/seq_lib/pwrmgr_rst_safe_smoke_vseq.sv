// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the smoke: no reset, so the flow runs to completion and proves the device
// does the work at all before any test tries to interrupt it.
class pwrmgr_rst_safe_smoke_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_smoke_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_smoke_test_seq_parameters


// Reset-safe smoke test: a shallow sleep and a wakeup, checked through the registers.
//
// The flow is the useful functional work the device exists to do, so reset landing anywhere in
// it interrupts something real rather than an idle loop.
class pwrmgr_rst_safe_smoke_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_smoke_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_low_power_wakeup();
endclass : pwrmgr_rst_safe_smoke_vseq


function pwrmgr_rst_safe_smoke_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_smoke_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_smoke_vseq::main_thread();
  // The registers return only once the device has asked for its clock, and the device reporting
  // that the processor may run is what says that happened, so the first access waits for it. Under
  // the stress wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf(
              "Low power operation %0d of %0d with wakeups 0x%0x",
              i + 1, test_params.num_trans, config_params.wakeups), UVM_MEDIUM)
    run_low_power_wakeup();
  end
endtask : main_thread


task pwrmgr_rst_safe_smoke_vseq::run_low_power_wakeup();
  wakeups_t       enabled_wakeups;
  uvm_reg_data_t  rd_value;

  // Let every wakeup source through, so the one the operation picks is the one that wakes the
  // device rather than one that happened to be enabled.
  enabled_wakeups = '1;
  csr_wr(.ptr(ral.wakeup_en[0]), .value(enabled_wakeups));
  csr_wr(.ptr(ral.intr_enable), .value(1'b1));

  // Ask for the transition. csr_wr rather than csr_update, because the write itself is what
  // arms the low power hint and it has to reach the device even when the mirror already agrees.
  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  // The device waits for the processor before it goes anywhere.
  discard_stale_observations();
  set_processor_sleeping(1'b1);
  wait_for_low_power_entry();

  // Now wake it.
  discard_stale_observations();
  set_wakeups(config_params.wakeups);
  wait_for_device_active();

  // Read what the device recorded about why it woke. Not compared here: these are written by
  // hardware, so the scoreboard predicts them from the stimulus and checks the read against that.
  wait_for_wakeup_interrupt();
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  // Leave the device where the next operation expects to find it: awake, nothing asking for a
  // wakeup, and the recorded reason cleared. Capture has to be disabled to clear wake_info.
  set_wakeups('0);
  set_processor_sleeping(1'b0);
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b1));
  csr_wr(.ptr(ral.wake_info), .value('1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b0));
endtask : run_low_power_wakeup
