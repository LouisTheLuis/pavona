// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the global escalation test: a few rounds, no reset from the framework.
class pwrmgr_rst_safe_global_esc_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_global_esc_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[1 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_global_esc_test_seq_parameters


// The alert handler escalating, which the device answers by resetting itself. It is held rather
// than pulsed: the device latches it and the reset it causes is what releases it.
class pwrmgr_rst_safe_global_esc_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_global_esc_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_escalation_round();
endclass : pwrmgr_rst_safe_global_esc_vseq


function pwrmgr_rst_safe_global_esc_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_global_esc_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_global_esc_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf("Escalation round %0d of %0d", i + 1, test_params.num_trans),
              UVM_MEDIUM)
    run_escalation_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_global_esc_vseq::run_escalation_round();
  uvm_reg_data_t rd_value;

  discard_stale_observations();
  set_escalation_reset(1'b1);

  // The device stops the processor fetching as soon as it acts on the escalation, which is what
  // says it was received. It is taken away there rather than held through the reset: the escalation
  // domain is reset as part of that, and an escalation asserted across it asks the receiver to
  // honor something it has no state for.
  wait_for_low_power_entry_started();
  set_escalation_reset(1'b0);

  // Then the device comes back, which is the boundary the checker compares at.
  wait_for_device_active();

  // The escalation is reported as a fault rather than as an ordinary reset request.
  csr_rd(.ptr(ral.escalate_reset_status), .value(rd_value));
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));

  set_escalation_reset(1'b0);
endtask : run_escalation_round
