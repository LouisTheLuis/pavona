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

  // Which wakeups software has enabled. At least one raised wakeup has to be enabled, or the
  // device would never come back.
  rand wakeups_t wakeups_en;

  // Whether the device records why it woke, and whether the wakeup interrupt is enabled. Both
  // are software's choice and neither changes whether the device wakes.
  rand bit disable_wakeup_capture;
  rand bit en_intr;

  // Leave what the device recorded from the previous round in place instead of clearing it, so
  // that the recorded reasons accumulate across rounds.
  rand bit keep_prior_wake_info;

  // What rstmgr forwards from software, as raw bits rather than the enumeration. Only one
  // encoding requests a reset and the rest have to leave the device alone, so the values that
  // are not members of the enumeration are exactly what this test needs to reach, and a
  // randomized enumeration would never produce them.
  rand bit [MUBI4W-1:0] sw_rst_req_raw;

  // How far apart to place low power entry and the wakeup, in cycles of their own clocks. The
  // interesting cases are the ones where they nearly coincide, so the device has to decide
  // between going to sleep and staying awake with both in flight.
  rand int unsigned cycles_before_transition;
  rand int unsigned cycles_before_early_wakeup;

  // Keep the main power domain up through the transition. Taking it down brings the glitch
  // path and the main power reset into a test whose purpose is the ordinary wakeup, so those
  // belong to their own sequences.
  rand bit main_pd_n;

  // Which of the two ways a low power transition can be abandoned. The processor starting to
  // execute again is a change that has to be placed inside the window; a non-volatile block
  // still being busy is a level the device reads when it checks.
  rand bit abort_by_processor;

  // Which peripherals ask for a reset, and which of those software has enabled. A request that
  // is not enabled has to leave the device alone, which is half of what the reset test checks.
  rand resets_t resets;
  rand resets_t resets_en;

  // A dip on the main power supply, and how long it lasts. The device treats a long enough dip
  // as a reset in its own right.
  // Which way the escalation side is broken: its clock taken away, or its reset held.
  // The lifecycle broadcast, as raw bits so the encodings that are not members of the
  // enumeration are reachable. Those are what the corruption test exists to send: the device
  // has to treat anything that is not a clean On as not enabled.
  rand bit [lc_ctrl_pkg::TxWidth-1:0] lc_hw_debug_en;
  rand bit [lc_ctrl_pkg::TxWidth-1:0] lc_dft_en;

  rand bit esc_malfunction_by_reset;

  rand bit power_glitch;
  rand int unsigned glitch_width_slow_clks;

  // Which of the non-volatile blocks is busy when the device checks. At least one has to be,
  // or the transition would complete and the round would not be an abort.
  rand bit flash_idle;
  rand bit otp_idle;
  rand bit lc_idle;

  `uvm_object_utils(pwrmgr_rst_safe_config_parameters)

  constraint wakeups_c {wakeups != '0;}

  constraint wakeups_en_c {
    solve wakeups before wakeups_en;
    (wakeups_en & wakeups) != '0;
  }
  constraint main_pd_n_c {main_pd_n == 1'b1;}

  constraint racing_cycles_c {
    cycles_before_transition inside {[1 : 12]};
    cycles_before_early_wakeup inside {[1 : 12]};
  }

  // The processor is the rarer of the two in the legacy test, and there is no reason to weight
  // them differently here: both paths are equally worth reaching.
  constraint abort_by_processor_c {abort_by_processor dist {1'b1 :/ 1, 1'b0 :/ 1};}

  constraint nvm_busy_c {
    solve abort_by_processor before flash_idle, otp_idle, lc_idle;
    if (!abort_by_processor) (flash_idle && otp_idle && lc_idle) == 1'b0;
  }

  constraint resets_c {resets != '0;}

  constraint resets_en_c {
    solve resets before resets_en;
    (resets_en & resets) != '0;
  }

  constraint power_glitch_c {
    soft power_glitch == 1'b0;
    glitch_width_slow_clks inside {[1 : 4]};
  }

  // Weighted so both clean encodings and the corrupt ones come up often enough to matter.
  constraint lc_broadcast_c {
    lc_hw_debug_en dist {lc_ctrl_pkg::On :/ 1, lc_ctrl_pkg::Off :/ 1, [0 : 15] :/ 2};
    lc_dft_en dist {lc_ctrl_pkg::On :/ 1, lc_ctrl_pkg::Off :/ 1, [0 : 15] :/ 2};
  }

  constraint sw_rst_req_raw_c {
    sw_rst_req_raw dist {MuBi4True :/ 2, MuBi4False :/ 1, [0 : 15] :/ 2};
  }

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
  extern task wait_for_device_active_at_start();
  extern task wait_for_low_power_entry();
  extern task wait_for_wakeup_interrupt();

  // Stimulus, as items to the two agents.
  extern task set_processor_sleeping(bit sleeping);
  extern task set_wakeups(wakeups_t wakeups);
  extern task set_nvm_idle(bit flash, bit otp, bit lc);
  extern task set_rom_response(int unsigned index, mubi4_t done, mubi4_t good);
  extern task wait_for_low_power_entry_started();
  extern task request_processor_wake_on_entry();
  extern task set_lifecycle_broadcast(bit [lc_ctrl_pkg::TxWidth-1:0] hw_debug_en,
                                      bit [lc_ctrl_pkg::TxWidth-1:0] dft_en);
  extern task set_escalation_reset(bit asserted);
  extern task set_escalation_malfunction(bit clk_stopped, bit rst_asserted);
  extern task interrupt_escalation_clock_for(int unsigned cycles);
  extern task force_invalid_state_at(pwrmgr_pkg::fast_pwr_state_e target);
  extern function void suspend_reset_forwarding_checks(bit suspend);
  extern task wait_for_invalid_state();
  extern task let_time_pass(int unsigned steps);
  protected bit cur_escalation_reset;
  protected bit cur_esc_clk_stopped;
  protected bit cur_esc_rst_asserted;
  extern task set_sw_reset_request(bit [MUBI4W-1:0] value);
  extern task set_reset_requests(resets_t resets);
  extern task send_power_glitch(int unsigned width_slow_clks);
  // As with the fast side, one item carries the whole of the always-on stimulus, so a helper
  // that sets one input restates the others as they stand.
  extern task set_processor_sleeping_after(bit sleeping, int unsigned delay_cycles);
  extern task set_wakeups_after(wakeups_t wakeups, int unsigned delay_cycles);

  extern task propagate_to_slow_domain();
endclass : pwrmgr_rand_rst_safe_base_vseq


function pwrmgr_rand_rst_safe_base_vseq::new(string name = "");
  super.new(name);
endfunction : new


// Spends time through the delay agent rather than through a delay statement. A sequence that
// has to go on working while a reset is scheduled against it needs to consume time somehow, and
// an item on the agent is torn down when reset arrives where a bare delay would run on.
task pwrmgr_rand_rst_safe_base_vseq::let_time_pass(int unsigned steps);
  delay_seq hold_seq;

  hold_seq = delay_seq::type_id::create("hold_seq");
  hold_seq.delay_time_steps = steps;
  hold_seq.start(p_sequencer.delay_sequencer_h);
endtask : let_time_pass


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


// The framework clears every interrupt register when the sequence ends, and it does that on the
// bus outside main_thread(), where the reset-safe base has no way to terminate it as a unit. Its
// own guard against this is `cfg.under_reset`, which nothing sets on the reset-safe path, so a
// reset landing during it runs straight through rather than standing down.
//
// Each sequence clears what it set instead, and anything added later has to do the same.
task pwrmgr_rand_rst_safe_base_vseq::post_start();
  do_clear_all_interrupts = 1'b0;
  super.post_start();
endtask : post_start


// Nothing. Every sequence establishes what it needs for itself, which is what the other ported
// blocks do. Waiting here would be wrong twice over: the framework calls this after reset has
// been released rather than while it is held, and it calls it again after a test that raised a
// fatal alert, where the device is already up and there is nothing to wait for. A sequence that
// needs the bus waits for the device to report that the processor may run, at the point it needs
// it.
task pwrmgr_rand_rst_safe_base_vseq::dut_init();
  // Nothing. Every sequence establishes what it needs for itself: the stress wrapper turns this
  // off and runs sequences one after another inside a single reset epoch, so a sequence that
  // relied on this having run would be relying on something that did not happen. The framework
  // also calls it after a test that raised a fatal alert, where the device is already up and
  // there is nothing to wait for.
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
  p_sequencer.clk_valid_fifo.flush();
  p_sequencer.fsm_fifo.flush();
endtask : discard_stale_observations


task pwrmgr_rand_rst_safe_base_vseq::wait_for_device_active();
  pwrmgr_active_item item;
  int unsigned       seen = 0;
  string             last = "nothing";
  int unsigned       queued;

  // What is already queued is reported before the wait, and what was consumed after it. A timeout
  // on an announcement has two causes that look the same from the message alone: the change never
  // happened, or it happened before this wait began and was taken by something else. Nothing queued
  // and nothing consumed is the first; announcements consumed that all carried the wrong value is
  // the second.
  queued = p_sequencer.active_fifo.used();
  `uvm_info(`gfn, $sformatf(
            "Waiting for the device to report the processor may run, %0d already queued",
            queued), UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.active_fifo.get(item);
                 seen++;
                 last = $sformatf("fetch_en 0x%0x at cycle %0d", item.fetch_en, item.clk_count);
                 if (item.fetch_en == lc_ctrl_pkg::On) break;
               end,
               $sformatf({"timed out waiting for the device to become active ",
                          "after %0d announcement(s), last %0s, %0d queued when the wait began"},
                         seen, last, queued),
               fast_obs_timeout_ns())
  `uvm_info(`gfn, "The device is active", UVM_MEDIUM)
endtask : wait_for_device_active


// The gate a sequence opens with, which is not the same question as the one above. The device
// announces the processor being let to run when that changes, so waiting for it works from a reset
// and does not work from anywhere else. A sequence started by the stress wrapper begins on a device
// that has been running since whichever sequence ran before it, and the announcement it would wait
// for went by long before it existed. The wrapper takes that wait once, for the reset epoch it
// owns, so there is nothing left here to wait for.
task pwrmgr_rand_rst_safe_base_vseq::wait_for_device_active_at_start();
  if (reset_ctrl_higher_seq) return;
  wait_for_device_active();
endtask : wait_for_device_active_at_start


task pwrmgr_rand_rst_safe_base_vseq::wait_for_low_power_entry();
  pwrmgr_flag_item item;
  int unsigned     seen = 0;
  string           last = "nothing";
  int unsigned       queued;

  queued = p_sequencer.low_power_fifo.used();
  `uvm_info(`gfn, $sformatf("Waiting for the device to report low power entry, %0d already queued",
                            queued), UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.low_power_fifo.get(item);
                 seen++;
                 last = $sformatf("value %0b at cycle %0d", item.value, item.clk_count);
                 if (item.value) break;
               end,
               $sformatf({"timed out waiting for low power entry ",
                          "after %0d announcement(s), last %0s, %0d queued when the wait began"},
                         seen, last, queued),
               fast_obs_timeout_ns())
endtask : wait_for_low_power_entry


// The interrupt is an event the device announces, so it is waited for rather than polled.
task pwrmgr_rand_rst_safe_base_vseq::wait_for_wakeup_interrupt();
  pwrmgr_flag_item item;
  int unsigned     seen = 0;
  string           last = "nothing";
  int unsigned       queued;

  queued = p_sequencer.intr_fifo.used();
  `uvm_info(`gfn, $sformatf(
            "Waiting for the device to raise the wakeup interrupt, %0d already queued",
            queued), UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.intr_fifo.get(item);
                 seen++;
                 last = $sformatf("value %0b at cycle %0d", item.value, item.clk_count);
                 if (item.value) break;
               end,
               $sformatf({"timed out waiting for the wakeup interrupt ",
                          "after %0d announcement(s), last %0s, %0d queued when the wait began"},
                         seen, last, queued),
               fast_obs_timeout_ns())
  `uvm_info(`gfn, "The wakeup interrupt was raised", UVM_MEDIUM)
endtask : wait_for_wakeup_interrupt


task pwrmgr_rand_rst_safe_base_vseq::set_processor_sleeping(bit sleeping);
  pwrmgr_fast_seq fast_item_seq;

  fast_item_seq = pwrmgr_fast_seq::type_id::create("fast_item_seq");
  fast_item_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(fast_item_seq.item, change_core_sleeping == 1'b1;
                                                     core_sleeping == sleeping;)
  fast_item_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_processor_sleeping


// The device only looks at these when it reaches the state that decides whether to complete the
// transition, and it reads them as levels, so a test that wants an abort can put them in place
// before asking for low power at all.


// The alert handler escalating. The device latches what it does with this, so it is held until
// a test takes it away rather than being pulsed.
task pwrmgr_rand_rst_safe_base_vseq::set_escalation_reset(bit asserted);
  pwrmgr_aon_seq esc_seq;

  cur_escalation_reset = asserted;
  esc_seq = pwrmgr_aon_seq::type_id::create("esc_seq");
  esc_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(esc_seq.item, change_escalation == 1'b1;
                                               escalation_reset == asserted;
                                               esc_clk_stopped == cur_esc_clk_stopped;
                                               esc_rst_asserted == cur_esc_rst_asserted;)
  esc_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_escalation_reset


// Taking the escalation clock away, or holding its reset. Either starves the counter the device
// uses to notice that escalation has stopped working.
task pwrmgr_rand_rst_safe_base_vseq::set_escalation_malfunction(bit clk_stopped,
                                                                bit rst_asserted);
  pwrmgr_aon_seq esc_malfunction_seq;

  cur_esc_clk_stopped  = clk_stopped;
  cur_esc_rst_asserted = rst_asserted;
  esc_malfunction_seq = pwrmgr_aon_seq::type_id::create("esc_malfunction_seq");
  esc_malfunction_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(esc_malfunction_seq.item, change_escalation == 1'b1;
                                                           escalation_reset == cur_escalation_reset;
                                                           esc_clk_stopped == clk_stopped;
                                                           esc_rst_asserted == rst_asserted;)
  esc_malfunction_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_escalation_malfunction


task pwrmgr_rand_rst_safe_base_vseq::set_nvm_idle(bit flash, bit otp, bit lc);
  pwrmgr_fast_seq nvm_idle_seq;

  nvm_idle_seq = pwrmgr_fast_seq::type_id::create("nvm_idle_seq");
  nvm_idle_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(nvm_idle_seq.item, change_idles == 1'b1;
                                                    flash_idle == flash;
                                                    otp_idle == otp;
                                                    lc_idle == lc;)
  nvm_idle_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_nvm_idle


// The device stops the processor fetching as soon as it starts a low power transition, several
// states before it decides whether to complete it. That announcement is what a test waits on to
// place an input inside the window, rather than reaching into the state it cannot see.
// Answer for one rom and leave the rest reporting a finished, trustworthy check. The device waits
// for every rom to report done before it reaches its active state, and treats a rom that is not
// good as a reason not to run, so naming one of them is how a test puts the check under pressure
// without stalling on the others. From here the driver owns the answer for the rest of the reset
// epoch: its own model of the check stands down, because a reply arriving later would overwrite
// what was asked for.
task pwrmgr_rand_rst_safe_base_vseq::set_rom_response(int unsigned index, mubi4_t done,
                                                      mubi4_t good);
  pwrmgr_fast_seq rom_response_seq;
  mubi4_t         want_done[pwrmgr_reg_pkg::NumRomInputs];
  mubi4_t         want_good[pwrmgr_reg_pkg::NumRomInputs];

  foreach (want_done[i]) begin
    want_done[i] = (i == index) ? done : MuBi4True;
    want_good[i] = (i == index) ? good : MuBi4True;
  end

  rom_response_seq = pwrmgr_fast_seq::type_id::create("rom_response_seq");
  rom_response_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(rom_response_seq.item,
                                 change_rom == 1'b1;
                                 foreach (rom_done[i]) rom_done[i] == want_done[i];
                                 foreach (rom_good[i]) rom_good[i] == want_good[i];)
  rom_response_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_rom_response


task pwrmgr_rand_rst_safe_base_vseq::wait_for_low_power_entry_started();
  pwrmgr_active_item item;
  int unsigned       seen = 0;
  string             last = "nothing";
  int unsigned       queued;

  queued = p_sequencer.active_fifo.used();
  `uvm_info(`gfn, $sformatf(
            "Waiting for the device to stop the processor fetching, %0d already queued",
            queued), UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.active_fifo.get(item);
                 seen++;
                 last = $sformatf("fetch_en 0x%0x at cycle %0d", item.fetch_en, item.clk_count);
                 if (item.fetch_en != lc_ctrl_pkg::On) break;
               end,
               $sformatf({"timed out waiting for the low power transition to start ",
                          "after %0d announcement(s), last %0s, %0d queued when the wait began"},
                         seen, last, queued),
               fast_obs_timeout_ns())
endtask : wait_for_low_power_entry_started


task pwrmgr_rand_rst_safe_base_vseq::set_wakeups(wakeups_t wakeups);
  pwrmgr_aon_seq aon_item_seq;

  aon_item_seq = pwrmgr_aon_seq::type_id::create("aon_item_seq");
  aon_item_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(aon_item_seq.item, change_wakeups == 1'b1;
                                                    wakeups == local::wakeups;)
  aon_item_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_wakeups


// Configuration written over the bus does not reach the slow domain until the device has
// synchronized it. This register reports when that has happened, so the transition is not
// started before the slow state machine can see what it was told.
// Software asks rstmgr for a reset, and rstmgr forwards the request here. Only the true
// encoding is a request; every other value has to leave the device alone, which is what makes
// the negative cases worth driving.
task pwrmgr_rand_rst_safe_base_vseq::set_processor_sleeping_after(bit sleeping,
                                                                  int unsigned delay_cycles);
  pwrmgr_fast_seq fast_seq;

  fast_seq = pwrmgr_fast_seq::type_id::create("fast_seq");
  fast_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(fast_seq.item, change_core_sleeping == 1'b1;
                                                core_sleeping == sleeping;
                                                apply_delay_cycles == delay_cycles;)
  fast_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_processor_sleeping_after


task pwrmgr_rand_rst_safe_base_vseq::set_wakeups_after(wakeups_t wakeups,
                                                       int unsigned delay_cycles);
  pwrmgr_aon_seq aon_seq;

  aon_seq = pwrmgr_aon_seq::type_id::create("aon_seq");
  aon_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(aon_seq.item, change_wakeups == 1'b1;
                                               wakeups == local::wakeups;
                                               change_sw_rst_req == 1'b1;
                                               sw_rst_req == MuBi4False;
                                               apply_delay_cycles == delay_cycles;)
  aon_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_wakeups_after


// Peripherals asking for a reset. Held until the test takes them away, because the device keeps
// resetting for as long as a request stands.
task pwrmgr_rand_rst_safe_base_vseq::set_reset_requests(resets_t resets);
  pwrmgr_aon_seq reset_req_seq;

  reset_req_seq = pwrmgr_aon_seq::type_id::create("reset_req_seq");
  reset_req_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(reset_req_seq.item, change_rstreqs == 1'b1;
                                                     rstreqs == resets;)
  reset_req_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_reset_requests


// A dip on the main power supply. The width belongs to the stimulus rather than to a delay in
// the sequence, so the driver applies it on the clock the supply belongs to.
task pwrmgr_rand_rst_safe_base_vseq::send_power_glitch(int unsigned width_slow_clks);
  pwrmgr_aon_seq glitch_seq;

  glitch_seq = pwrmgr_aon_seq::type_id::create("glitch_seq");
  glitch_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(glitch_seq.item, power_glitch == 1'b1;
                                                  glitch_width_slow_clks == width_slow_clks;)
  glitch_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : send_power_glitch


task pwrmgr_rand_rst_safe_base_vseq::set_sw_reset_request(bit [MUBI4W-1:0] value);
  pwrmgr_aon_seq aon_seq;

  aon_seq = pwrmgr_aon_seq::type_id::create("aon_seq");
  aon_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(aon_seq.item, change_sw_rst_req == 1'b1;
                                               sw_rst_req == value;)
  aon_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : set_sw_reset_request


task pwrmgr_rand_rst_safe_base_vseq::propagate_to_slow_domain();
  csr_wr(.ptr(ral.cfg_cdc_sync), .value(1'b1));
  csr_spinwait(.ptr(ral.cfg_cdc_sync), .exp_data(1'b0), .spinwait_delay_ns(100),
               .timeout_ns(fast_obs_timeout_ns()));
endtask : propagate_to_slow_domain


// Take the escalation clock away for a measured number of cycles and give it back. The count is
// the stimulus, so the driver spends it on the clock it is counted in.
task pwrmgr_rand_rst_safe_base_vseq::interrupt_escalation_clock_for(int unsigned cycles);
  pwrmgr_aon_seq esc_clk_interrupt_seq;

  esc_clk_interrupt_seq = pwrmgr_aon_seq::type_id::create("esc_clk_interrupt_seq");
  esc_clk_interrupt_seq.item = pwrmgr_aon_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(esc_clk_interrupt_seq.item, change_escalation == 1'b1;
                                                             escalation_reset == cur_escalation_reset;
                                                             esc_rst_asserted == cur_esc_rst_asserted;
                                                             esc_clk_stopped == 1'b1;
                                                             esc_clk_stopped_cycles == cycles;)
  esc_clk_interrupt_seq.start(p_sequencer.aon_sequencer_h, this);
endtask : interrupt_escalation_clock_for




// A device held in its invalid state cannot forward a reset request, which is what two of the
// checks on the reset request interface require of a working device. They are suspended for as
// long as a test holds the device there and put back once it is running again. Only those two
// are affected; the escalation and software reset checks on the same interface stay on, because
// a wedged device is still expected to behave for those.
function void pwrmgr_rand_rst_safe_base_vseq::suspend_reset_forwarding_checks(bit suspend);
  cfg.pwrmgr_rstreqs_sva_vif.disable_hw_reset_sva = suspend;
endfunction : suspend_reset_forwarding_checks


// Ask for the state machine to be sent to its invalid state when it reaches a named state.
// Naming the state is the sequence's part; waiting for it belongs to the driver, which owns that
// interface.
task pwrmgr_rand_rst_safe_base_vseq::force_invalid_state_at(
    pwrmgr_pkg::fast_pwr_state_e target);
  pwrmgr_fast_seq fsm_invalid_seq;

  fsm_invalid_seq = pwrmgr_fast_seq::type_id::create("fsm_invalid_seq");
  fsm_invalid_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(fsm_invalid_seq.item, force_fsm_invalid == 1'b1;
                                                       invalid_at_state == target;)
  fsm_invalid_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : force_invalid_state_at


// The device announces the state it is in, so this is an ordinary wait on a transaction.
task pwrmgr_rand_rst_safe_base_vseq::wait_for_invalid_state();
  pwrmgr_fsm_item item;
  int unsigned    seen = 0;
  string          last = "nothing";
  int unsigned       queued;

  queued = p_sequencer.fsm_fifo.used();
  `uvm_info(`gfn, $sformatf("Waiting for the device to reach its invalid state, %0d already queued",
                            queued), UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.fsm_fifo.get(item);
                 seen++;
                 last = $sformatf("%0s at cycle %0d", item.state.name(), item.clk_count);
                 if (item.state == pwrmgr_pkg::FastPwrStateInvalid) break;
               end,
               $sformatf({"timed out waiting for the device to reach its invalid state ",
                          "after %0d announcement(s), last %0s, %0d queued when the wait began"},
                         seen, last, queued),
               fast_obs_timeout_ns())
endtask : wait_for_invalid_state



// Ask for the processor to start executing again as the device commits to a low power
// transition. The sequence states the intent; the driver places it, holding the device where it
// waits for its clocks until the wake is applied, so there is nothing to race.
task pwrmgr_rand_rst_safe_base_vseq::request_processor_wake_on_entry();
  pwrmgr_fast_seq wake_on_entry_seq;

  wake_on_entry_seq = pwrmgr_fast_seq::type_id::create("wake_on_entry_seq");
  wake_on_entry_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(wake_on_entry_seq.item, change_core_sleeping == 1'b1;
                                                         core_sleeping == 1'b1;
                                                         wake_processor_on_entry == 1'b1;)
  wake_on_entry_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : request_processor_wake_on_entry



// What the lifecycle controller is broadcasting. Held until changed, because the device reads it
// as a level whenever it needs to decide whether debug is allowed. The driver is what holds it,
// so this item says only that the broadcast is moving and a later item about something else
// leaves it where it is.
task pwrmgr_rand_rst_safe_base_vseq::set_lifecycle_broadcast(
    bit [lc_ctrl_pkg::TxWidth-1:0] hw_debug_en, bit [lc_ctrl_pkg::TxWidth-1:0] dft_en);
  pwrmgr_fast_seq lc_broadcast_seq;

  lc_broadcast_seq = pwrmgr_fast_seq::type_id::create("lc_broadcast_seq");
  lc_broadcast_seq.item = pwrmgr_fast_item::type_id::create("req");
  `DV_CHECK_RANDOMIZE_WITH_FATAL(lc_broadcast_seq.item, change_lc == 1'b1;
                                                        lc_hw_debug_en == hw_debug_en;
                                                        lc_dft_en == dft_en;)
  lc_broadcast_seq.start(p_sequencer.fast_sequencer_h, this);
endtask : set_lifecycle_broadcast
