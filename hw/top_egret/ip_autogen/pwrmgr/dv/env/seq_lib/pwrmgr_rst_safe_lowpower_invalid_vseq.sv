// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the invalid state test: one target state per reset loop, so the power-on reset
// the framework applies between loops is what recovers the device. Nothing here applies a reset
// itself.
class pwrmgr_rst_safe_lowpower_invalid_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_lowpower_invalid_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops == 4;}

  constraint num_trans_c {num_trans == 1;}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_lowpower_invalid_test_seq_parameters


// The device's fast state machine is built so a fault drives it to a state it cannot leave except
// by reset. This checks it gets there and stays there.
//
// Nothing here reaches into the device: the sequence names the state and the driver waits for it.
// The device is sent along the path its own slow state machine uses, so the encoding stays legal.
// The device then announces the state it is in, so the check is an ordinary wait on a transaction.
class pwrmgr_rst_safe_lowpower_invalid_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_lowpower_invalid_vseq)

  // Which state to send the device to invalid from. One per reset loop, so the sweep is spread
  // across the loops rather than driven by a reset this sequence applies.
  protected int unsigned target_index;

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task start_low_power_transition();
endclass : pwrmgr_rst_safe_lowpower_invalid_vseq


function pwrmgr_rst_safe_lowpower_invalid_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_lowpower_invalid_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_lowpower_invalid_vseq::main_thread();
  pwrmgr_pkg::fast_pwr_state_e targets[] = '{pwrmgr_pkg::FastPwrStateFallThrough,
                                             pwrmgr_pkg::FastPwrStateNvmIdleChk,
                                             pwrmgr_pkg::FastPwrStateLowPowerPrep,
                                             pwrmgr_pkg::FastPwrStateReqPwrDn};

  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  suspend_reset_forwarding_checks(1'b0);
  `DV_CHECK_RANDOMIZE_FATAL(config_params)
  `uvm_info(`gfn, $sformatf("Going invalid from %0s", targets[target_index].name()),
            UVM_MEDIUM)

  // The request is placed first and the driver evaluates it every cycle, so it does not matter
  // whether the device has started moving yet.
  // Suspended from here because the device is about to stop forwarding anything, and dropped at the
  // head of the next attempt: the reset that frees the device also kills this thread, so nothing
  // after the wait below runs. Reset already holds these checks off, so the window is covered.
  suspend_reset_forwarding_checks(1'b1);
  force_invalid_state_at(targets[target_index]);
  start_low_power_transition();
  wait_for_invalid_state();

  target_index = (target_index + 1) % targets.size();

  // Work for the reset to land in, and a property worth checking while it does: a device held in
  // its invalid state ignores whatever else it is asked to do, and the checker holds that it cannot
  // leave without a reset.
  //
  // This is not a wait dressed up as work. The reset has to assert while the sequence is still
  // doing something, and the last loop has to finish on its own, so the rounds outlast the window
  // the reset is scheduled in.
  repeat (InvalidStateHoldRounds) begin
    set_wakeups(config_params.wakeups);
    let_time_pass(InvalidStateHoldSteps);
    set_reset_requests(config_params.resets);
    let_time_pass(InvalidStateHoldSteps);
    set_wakeups('0);
    let_time_pass(InvalidStateHoldSteps);
    set_reset_requests('0);
    let_time_pass(InvalidStateHoldSteps);
  end
endtask : main_thread


task pwrmgr_rst_safe_lowpower_invalid_vseq::start_low_power_transition();
  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  stage_clock_enables();
  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  set_processor_sleeping(1'b1);
endtask : start_low_power_transition
