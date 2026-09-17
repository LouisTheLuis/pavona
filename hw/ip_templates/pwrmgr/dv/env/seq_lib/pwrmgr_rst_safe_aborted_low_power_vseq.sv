// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the aborted low power test: several rounds, no reset.
class pwrmgr_rst_safe_aborted_low_power_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_aborted_low_power_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[2 : 5]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_aborted_low_power_test_seq_parameters


// A low power transition the device starts and then abandons, in the two ways it distinguishes.
//
// The processor can start executing again after saying it was asleep, reported as a fall through,
// or a non-volatile block can still be busy when the device checks, reported as an abort. Either
// way the device raises the wakeup interrupt, records nothing about why it woke, and returns to
// running without powering down.
//
// Idleness is read as a level, so putting a block to work before asking for low power is enough.
// The processor waking is a change that has to land after the transition starts and before the
// device decides, so it is placed against the announcement that fetching has stopped.
class pwrmgr_rst_safe_aborted_low_power_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_aborted_low_power_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_abort_round(bit by_processor);
endclass : pwrmgr_rst_safe_aborted_low_power_vseq


function pwrmgr_rst_safe_aborted_low_power_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_aborted_low_power_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_aborted_low_power_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf("Aborted low power round %0d of %0d: abandoned by the %0s",
                              i + 1, test_params.num_trans,
                              config_params.abort_by_processor ? "processor"
                                                               : "non-volatile blocks"),
              UVM_MEDIUM)
    run_abort_round(config_params.abort_by_processor);
  end
endtask : main_thread


task pwrmgr_rst_safe_aborted_low_power_vseq::run_abort_round(bit by_processor);
  uvm_reg_data_t rd_value;

  // Recording has to be on for the device to report which of the two happened.
  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  csr_wr(.ptr(ral.intr_enable.wakeup), .value(1'b1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b1));
  csr_wr(.ptr(ral.wake_info), .value('1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b0));

  // The busy block is put in place first when that is what will abandon the transition. It is
  // read as a level at the point the device checks, so it needs no placing.
  if (!by_processor) begin
    set_nvm_idle(.flash(config_params.flash_idle), .otp(config_params.otp_idle),
                 .lc(config_params.lc_idle));
  end

  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  discard_stale_observations();
  if (by_processor) begin
    // The driver holds the device where it waits for its clocks, applies the wake, and only
    // then lets it go on to decide. Nothing here has to be timed.
    request_processor_wake_on_entry();
  end else begin
    set_processor_sleeping(1'b1);
  end

  // One wait, and on something that happens: both ways of abandoning raise the wakeup interrupt.
  //
  // The window itself is deliberately not waited for. That is a question about a level while the
  // announcements carry changes, so the wait would never return either way. Placing the processor's
  // wake inside the window belongs to the driver, which owns that interface.
  wait_for_wakeup_interrupt();

  // The device abandoned the transition, so it recorded which of the two reasons applied and
  // nothing about a wakeup. Read, not judged here. What the device recorded is the checker's to
  // predict and compare; this sequence only asks for the abandonment and reads.
  csr_rd(.ptr(ral.wake_info), .value(rd_value));
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  // Put everything back so the next round starts from a device that can complete a transition.
  set_processor_sleeping(1'b0);
  if (!by_processor) set_nvm_idle(.flash(1'b1), .otp(1'b1), .lc(1'b1));
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b1));
  csr_wr(.ptr(ral.wake_info), .value('1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b0));
endtask : run_abort_round
