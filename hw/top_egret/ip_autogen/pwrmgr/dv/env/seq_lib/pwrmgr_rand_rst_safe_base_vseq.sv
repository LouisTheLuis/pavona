// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape: how many reset epochs, how many operations in each, and when reset lands.
class pwrmgr_rst_safe_test_seq_parameters extends dv_test_seq_parameters;

  // Slow clock cycles between the epoch starting and reset being applied. The delay agent runs
  // this on the power-on reset domain, which is the slow clock, so the numbers here are slow
  // cycles and not bus cycles.
  //
  // The range is derived from how long one operation takes on this top, which the package works
  // out from the clock frequencies the top is built with.
  rand int unsigned reset_delay_steps;

  `uvm_object_utils(pwrmgr_rst_safe_test_seq_parameters)

  constraint reset_enable_c {reset_testing inside {DISABLE, ENABLE};}

  constraint reset_loops_c {
    if (reset_testing == ENABLE) num_reset_loops inside {[2 : 5]};
    else                         num_reset_loops == 1;
  }

  constraint num_trans_c {num_trans inside {[1 : 3]};}

  // Reset has to land while the operation is still going. The upper bound is three quarters of
  // how long one takes on this top, so it stays inside whatever the operation count randomizes
  // to; a delay that outlives the workload is not merely a weaker test, because the base sequence
  // warns when the main thread finishes first and a warning fails the run.
  constraint reset_delay_steps_c {
    reset_delay_steps inside {[2 : (LowPowerOpAonCycles * 3) / 4]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_test_seq_parameters


// Choices that can change from one operation to the next.
class pwrmgr_rst_safe_config_parameters extends dv_config_parameters;

  // Which peripherals ask for a wakeup. At least one, or the device would never come back and
  // the operation would not be a wakeup at all.
  rand wakeups_t wakeups;

  // Keep the main power domain up through the transition. Taking it down brings the glitch
  // path and the main power reset into a test whose purpose is the ordinary wakeup, so those
  // belong to their own sequences.
  rand bit main_pd_n;

  `uvm_object_utils(pwrmgr_rst_safe_config_parameters)

  constraint wakeups_c {wakeups != '0;}
  constraint main_pd_n_c {main_pd_n == 1'b1;}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_config_parameters


// Reset-safe functional base for the power manager.
//
// Everything this sequence waits on is a transaction. The device announces when the processor
// may run and when it has entered low power, and those announcements are what the flow below
// is built on, so no part of it samples a pin or counts cycles to decide what happened.
class pwrmgr_rand_rst_safe_base_vseq extends cip_rand_rst_safe_base_vseq #(
    .RAL_T              (pwrmgr_reg_block),
    .CFG_T              (pwrmgr_env_cfg),
    .COV_T              (pwrmgr_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T(pwrmgr_rst_safe_virtual_sequencer),
    .TEST_PARAMS_T      (pwrmgr_rst_safe_test_seq_parameters),
    .CONFIG_PARAMS_T    (pwrmgr_rst_safe_config_parameters)
  );

  `uvm_object_utils(pwrmgr_rand_rst_safe_base_vseq)

  // How long a wait on something the device announces is given before it fails, counted in
  // always-on clock cycles. A duration would not do: the clocks are randomized, so the same
  // number of nanoseconds buys a different number of cycles on every seed, and what these waits
  // are waiting for is paced by the always-on clock rather than by wall time.
  localparam int unsigned FastObsTimeoutAonCycles = 2_000;

  extern function new(string name = "");

  extern virtual task reset_trigger_thread();
  extern virtual task main_thread();
  extern virtual task dut_init();
  extern virtual task post_start();

  // Synchronization on what the device announced.
  // Converts the cycle count above using the period the clock was actually given.
  extern protected function int unsigned fast_obs_timeout_ns();
  extern task discard_stale_observations();
  extern task wait_for_device_active();
  extern task wait_for_low_power_entry();
  extern task wait_for_wakeup_interrupt();

  // Stimulus, as items to the two agents.
  extern task set_processor_sleeping(bit sleeping);
  extern task set_wakeups(wakeups_t wakeups);

  extern task propagate_to_slow_domain();
endclass : pwrmgr_rand_rst_safe_base_vseq


function pwrmgr_rand_rst_safe_base_vseq::new(string name = "");
  super.new(name);
endfunction : new


task pwrmgr_rand_rst_safe_base_vseq::reset_trigger_thread();
  delay_seq del_seq;
  reset_seq rst_seq;

  del_seq = delay_seq::type_id::create("del_seq");
  del_seq.delay_time_steps = test_params.reset_delay_steps;
  del_seq.start(p_sequencer.delay_sequencer_h);

  `uvm_info(`gfn, "Triggering the power-on reset", UVM_MEDIUM)
  rst_seq = reset_seq::type_id::create("rst_seq");
  rst_seq.start(p_sequencer.clk_rst_sequencer_h);
endtask : reset_trigger_thread


task pwrmgr_rand_rst_safe_base_vseq::main_thread();
  `uvm_fatal(`gfn, "A derived reset-safe sequence has to implement main_thread()")
endtask : main_thread


// Nothing. Every sequence establishes what it needs for itself, which is what the other ported
// blocks do. Waiting here would be wrong twice over: the framework calls this after reset has
// been released rather than while it is held, and it calls it again after a test that raised a
// fatal alert, where the device is already up and there is nothing to wait for. A sequence that
// needs the bus waits for the device to report that the processor may run, at the point it needs
// it.
// The framework clears every interrupt register when the sequence ends, and it does that on the
// bus outside main_thread(), where the reset-safe base has no way to terminate it as a unit. Its
// own guard against this is `cfg.under_reset`, which nothing sets on the reset-safe path, so a
// reset landing during it runs straight through rather than standing down.
//
// Each sequence clears what it set instead. The smoke sequence writes `intr_state` itself, and
// anything added later has to do the same.
task pwrmgr_rand_rst_safe_base_vseq::post_start();
  do_clear_all_interrupts = 1'b0;
  super.post_start();
endtask : post_start


task pwrmgr_rand_rst_safe_base_vseq::dut_init();
endtask : dut_init


// The macro wants a duration, so the cycle count is turned into one here using the period the
// clock was actually given rather than a figure fixed when this was written.
function int unsigned pwrmgr_rand_rst_safe_base_vseq::fast_obs_timeout_ns();
  // Widened before multiplying. The period is an int, and on a top whose always-on clock is a
  // long way below its bus clock the product leaves thirty two bits: it wraps to a small number
  // and the wait then fails long before the device has had time to answer.
  return int'((longint'(FastObsTimeoutAonCycles) * cfg.slow_clk_rst_vif.clk_period_ps) / 1000);
endfunction : fast_obs_timeout_ns


// Throw away anything already sitting in the fifos before new stimulus is applied. Otherwise the
// next wait is satisfied by an item from earlier, and the sequence carries on as though the device
// had responded to something it has not seen yet.
task pwrmgr_rand_rst_safe_base_vseq::discard_stale_observations();
  p_sequencer.active_fifo.flush();
  p_sequencer.low_power_fifo.flush();
  p_sequencer.intr_fifo.flush();
endtask : discard_stale_observations


task pwrmgr_rand_rst_safe_base_vseq::wait_for_device_active();
  pwrmgr_active_item item;

  `uvm_info(`gfn, "Waiting for the device to report the processor may run", UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.active_fifo.get(item);
                 if (item.fetch_en == lc_ctrl_pkg::On) break;
               end,
               "timed out waiting for the device to become active", fast_obs_timeout_ns())
  `uvm_info(`gfn, "The device is active", UVM_MEDIUM)
endtask : wait_for_device_active


task pwrmgr_rand_rst_safe_base_vseq::wait_for_low_power_entry();
  pwrmgr_flag_item item;

  `uvm_info(`gfn, "Waiting for the device to report low power entry", UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.low_power_fifo.get(item);
                 if (item.value) break;
               end,
               "timed out waiting for low power entry", fast_obs_timeout_ns())
  `uvm_info(`gfn, "The device has entered low power", UVM_MEDIUM)
endtask : wait_for_low_power_entry


// The interrupt is an event the device announces, so it is waited for rather than polled.
task pwrmgr_rand_rst_safe_base_vseq::wait_for_wakeup_interrupt();
  pwrmgr_flag_item item;

  `uvm_info(`gfn, "Waiting for the device to raise the wakeup interrupt", UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.intr_fifo.get(item);
                 if (item.value) break;
               end,
               "timed out waiting for the wakeup interrupt", fast_obs_timeout_ns())
  `uvm_info(`gfn, "The wakeup interrupt was raised", UVM_MEDIUM)
endtask : wait_for_wakeup_interrupt


task pwrmgr_rand_rst_safe_base_vseq::set_processor_sleeping(bit sleeping);
  pwrmgr_fast_seq seq;

  seq = pwrmgr_fast_seq::type_id::create("fast_item_seq");
  seq.core_sleeping_value = sleeping;
  seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_processor_sleeping


task pwrmgr_rand_rst_safe_base_vseq::set_wakeups(wakeups_t wakeups);
  pwrmgr_aon_seq seq;

  seq = pwrmgr_aon_seq::type_id::create("aon_item_seq");
  seq.wakeups_value = wakeups;
  seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_wakeups


// Configuration written over the bus does not reach the slow domain until the device has
// synchronized it. This register reports when that has happened, so the transition is not
// started before the slow state machine can see what it was told.
task pwrmgr_rand_rst_safe_base_vseq::propagate_to_slow_domain();
  csr_wr(.ptr(ral.cfg_cdc_sync), .value(1'b1));
  csr_spinwait(.ptr(ral.cfg_cdc_sync), .exp_data(1'b0), .spinwait_delay_ns(100),
               .timeout_ns(fast_obs_timeout_ns()));
endtask : propagate_to_slow_domain
