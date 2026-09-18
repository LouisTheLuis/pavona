// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the invalid state sweep: one target state per reset loop, so the reset the
// framework applies between loops is what recovers the device.
class pwrmgr_rst_safe_fsm_invalid_sweep_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_fsm_invalid_sweep_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops == 4;}

  constraint num_trans_c {num_trans == 1;}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_fsm_invalid_sweep_test_seq_parameters


// The state to corrupt the device from, drawn from the object's own seed so an unrelated edit does
// not move which state a given seed attacks. The invalid state is the destination, not a source.
class pwrmgr_rst_safe_fsm_invalid_target extends uvm_object;

  rand pwrmgr_pkg::fast_pwr_state_e state;

  constraint state_c {state != pwrmgr_pkg::FastPwrStateInvalid;}

  `uvm_object_utils_begin(pwrmgr_rst_safe_fsm_invalid_target)
    `uvm_field_enum(pwrmgr_pkg::fast_pwr_state_e, state, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_fsm_invalid_target


// Sends the device to its terminal state from every state it passes through, rather than from the
// handful the two existing invalid tests name.
//
// The fault input overrides whatever the state machine's case decided, so asserting it while the
// device sits in any state produces the transition out of that state. Which one is exercised is
// decided by where the device is when the fault arrives.
//
// The existing tests arm the fault only once the device is active, by which time the power-up walk
// is over and ten of the nineteen states are unreachable. This arms it as soon as the driver can
// take it, so a target on that walk is caught on the way through.
class pwrmgr_rst_safe_fsm_invalid_sweep_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_fsm_invalid_sweep_vseq)

  // How the device is made to visit the target state.
  typedef enum {
    // Reached by the device on its own as it powers up, so the fault is armed and nothing else
    // is asked of it.
    PathPowerUp,
    // Reached only on the way into low power, so the device is asked to go to sleep.
    PathLowPower,
    // Reached only on the way into a reset, so the device is asked for one.
    PathReset
  } target_path_e;

  protected pwrmgr_rst_safe_fsm_invalid_target target;

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected function target_path_e path_to(pwrmgr_pkg::fast_pwr_state_e state);
  extern protected task request_low_power();
  extern protected task request_reset();
  extern protected task hold_the_device_invalid();
endclass : pwrmgr_rst_safe_fsm_invalid_sweep_vseq


function pwrmgr_rst_safe_fsm_invalid_sweep_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_fsm_invalid_sweep_test_seq_parameters::get_type());
endfunction : new


function pwrmgr_rst_safe_fsm_invalid_sweep_vseq::target_path_e
    pwrmgr_rst_safe_fsm_invalid_sweep_vseq::path_to(pwrmgr_pkg::fast_pwr_state_e state);
  case (state)
    pwrmgr_pkg::FastPwrStateDisClks,
    pwrmgr_pkg::FastPwrStateFallThrough,
    pwrmgr_pkg::FastPwrStateNvmIdleChk,
    pwrmgr_pkg::FastPwrStateLowPowerPrep,
    pwrmgr_pkg::FastPwrStateReqPwrDn: return PathLowPower;

    pwrmgr_pkg::FastPwrStateNvmShutDown,
    pwrmgr_pkg::FastPwrStateResetPrep,
    pwrmgr_pkg::FastPwrStateResetWait: return PathReset;

    // Everything else is on the walk out of reset, up to and including the state the device
    // rests in once it is running.
    default: return PathPowerUp;
  endcase
endfunction : path_to


task pwrmgr_rst_safe_fsm_invalid_sweep_vseq::main_thread();
  target_path_e path;

  target = pwrmgr_rst_safe_fsm_invalid_target::type_id::create("target");
  `DV_CHECK_RANDOMIZE_FATAL(target)
  `DV_CHECK_RANDOMIZE_FATAL(config_params)
  path = path_to(target.state);
  `uvm_info(`gfn, $sformatf("Going invalid from %0s, reached by the %0s path", target.state.name(),
                            path.name()), UVM_LOW)

  // Suspended before the fault is armed, because a device wedged in its terminal state cannot honor
  // a contract about forwarding. Dropped at the head of the next attempt, since the reset that
  // frees the device also kills this thread. Reset already holds these checks off.
  suspend_reset_forwarding_checks(1'b1);

  // Armed as early as the driver can accept it, which is the point of the sequence. The driver
  // evaluates the request every cycle, so a state the device is still walking towards is caught
  // when it arrives.
  wait_for_fast_driver_running();
  force_invalid_state_at(target.state);

  // A power-up target needs no stimulus, and must not be waited on either: the device is wedged
  // before it ever reports that the processor may run, so a wait for that would never return.
  if (path != PathPowerUp) begin
    wait_for_device_active_at_start();
    if (path == PathLowPower) request_low_power();
    else                      request_reset();
  end

  wait_for_invalid_state();
  hold_the_device_invalid();
endtask : main_thread


task pwrmgr_rst_safe_fsm_invalid_sweep_vseq::request_low_power();
  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  stage_clock_enables();
  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  set_processor_sleeping(1'b1);
endtask : request_low_power


task pwrmgr_rst_safe_fsm_invalid_sweep_vseq::request_reset();
  csr_wr(.ptr(ral.reset_en), .value(config_params.resets_en));
  propagate_to_slow_domain();

  set_reset_requests(config_params.resets);
endtask : request_reset


// Work for the reset to land in, and a property worth checking while it does: a device held in its
// terminal state ignores whatever else it is asked to do, and the checker holds that it cannot
// leave without a reset. None of it touches the bus, which a device attacked on its way up never
// brought back.
task pwrmgr_rst_safe_fsm_invalid_sweep_vseq::hold_the_device_invalid();
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
endtask : hold_the_device_invalid
