// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the escalation timeout test: a few rounds, no reset from the framework.
class pwrmgr_rst_safe_escalation_timeout_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_escalation_timeout_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[1 : 3]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_escalation_timeout_test_seq_parameters


// The device watches its escalation clock and resets itself if that clock stops for long enough.
//
// Both directions are worth a round. The short stop is the awkward one, because carrying on is the
// absence of an event: it is checked by leaving a bounded window through the delay agent, which
// spends the time as stimulus that reset tears down, then confirming the device is still running.
class pwrmgr_rst_safe_escalation_timeout_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_escalation_timeout_vseq)

  extern function new(string name = "");
  extern virtual task pre_start();
  extern virtual task main_thread();
  extern protected task run_timeout_round(bit long_enough);
endclass : pwrmgr_rst_safe_escalation_timeout_vseq


function pwrmgr_rst_safe_escalation_timeout_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_escalation_timeout_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_escalation_timeout_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    // Both directions every round, the short one first so the device is known to be running
    // when the long one starts.
    run_timeout_round(.long_enough(1'b0));
    run_timeout_round(.long_enough(1'b1));
  end
endtask : main_thread


task pwrmgr_rst_safe_escalation_timeout_vseq::run_timeout_round(bit long_enough);
  uvm_reg_data_t rd_value;

  discard_stale_observations();

  if (long_enough) begin
    `uvm_info(`gfn, "Stopping the escalation clock and leaving it stopped", UVM_MEDIUM)
    set_escalation_malfunction(.clk_stopped(1'b1), .rst_asserted(1'b0));

    // Stopping the processor fetching is the device saying it has noticed. The clock is given
    // back there: held away through the reset as well, the device would find it still missing
    // when it came back and reset again without end.
    wait_for_low_power_entry_started();
    set_escalation_malfunction(.clk_stopped(1'b0), .rst_asserted(1'b0));

    wait_for_device_active();
    csr_rd(.ptr(ral.escalate_reset_status), .value(rd_value));
  end else begin
    // A reset would take this back to its reset value, so writing it before the interruption
    // and finding it afterwards is what says no reset happened. Written after is worth
    // nothing: it would read back either way.
    csr_wr(.ptr(ral.intr_enable.wakeup), .value(1'b1));

    `uvm_info(`gfn, $sformatf("Interrupting the escalation clock for %0d cycles",
                              EscTimeoutSafeCycles), UVM_MEDIUM)
    interrupt_escalation_clock_for(EscTimeoutSafeCycles);

    // Read, not judged here: whether the device kept what software wrote is the checker's to
    // say, and it is the one that knows whether a reset happened.
    csr_rd(.ptr(ral.intr_enable.wakeup), .value(rd_value));
  end
endtask : run_timeout_round


// The device raises its fatal alert for this on purpose, so the blanket check for an
// unexplained alert is stood down. The scoreboard still checks that each alert is accounted
// for by something it observed.
task pwrmgr_rst_safe_escalation_timeout_vseq::pre_start();
  expect_fatal_alerts = 1'b1;
  super.pre_start();
endtask : pre_start
