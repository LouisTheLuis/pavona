// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe scoreboard for the power manager.
//
// Everything it learns arrives as a transaction from a monitor or the bus. It samples no signal
// and waits on no clock edge, so only a publication or a reset wakes a worker.
class pwrmgr_rst_safe_scoreboard extends cip_rst_safe_scoreboard #(
    .CFG_T(pwrmgr_env_cfg),
    .RAL_T(pwrmgr_reg_block),
    .COV_T(pwrmgr_rst_safe_env_cov)
  );

  `uvm_component_utils(pwrmgr_rst_safe_scoreboard)
  `uvm_component_new

  uvm_tlm_analysis_fifo #(pwrmgr_wakeup_item)    wakeup_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_reset_req_item) reset_req_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_active_item)    active_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      low_power_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      intr_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      glitch_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      esc_timeout_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_fast_stim_item) stim_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_fsm_item)       fsm_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      clk_valid_fifo;

  // Names each publication in the order it was made, so one worker can take from the ports in that
  // order. Separate workers on separate queues have no ordering between them.
  uvm_tlm_analysis_fifo #(pwrmgr_aon_obs_kind_e)  aon_dir_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_fast_obs_kind_e) fast_dir_fifo;

  protected pwrmgr_wakeup_item    last_wakeup;
  protected pwrmgr_reset_req_item last_reset_req;
  protected pwrmgr_active_item    last_active;
  protected pwrmgr_flag_item      last_intr;

  // What the device is expected to have recorded, built from the stimulus rather than anything it
  // reports, since the registers below are written by hardware.
  protected bit       in_low_power;

  // Whether the device is recording why it woke. Recording runs from low power entry until software
  // disables it, so a wakeup raised after the device is running again is still recorded.
  protected bit       record_en;
  protected wakeups_t cur_wakeups;
  // The device masks the sources with a copy of the enable taken in its own clock domain, refreshed
  // only when software asks. An enable written without that refresh changes nothing.
  protected wakeups_t synced_wakeup_en;

  typedef struct packed {
    longint unsigned index;
    bit [TL_DW-1:0]  value;
  } volatile_update_t;
  protected volatile_update_t read_history[string][$];
  protected longint unsigned  update_count[string];
  // The registers the device writes itself advance only while its fast clock runs, which stops for
  // low power, so what is recorded is gated on this while the sources keep changing.
  protected bit       cur_clk_running;
  // The state machine is meant to be unable to leave its invalid state except by reset, so once
  // it is seen there anything else is a failure of the thing the invalid state tests check.
  protected bit       saw_invalid_state;
  // Whether the main supply has been seen up since the last reset, so that it coming back is
  // not mistaken for it going away.
  protected bit       saw_main_power_up;
  // Whether the device is already holding a fault, so the alert is asked for once rather than
  // on every commit while it stands.
  protected bit       exp_fault_alert;
  protected bit       exp_fault_glitch;
  protected bit       exp_fault_esc_timeout;
  protected bit       exp_fault_intg;

  // The device locks its control register for a low power transition, taking the lock when the
  // transition begins and giving it back when it is running again.
  protected bit       exp_ctrl_locked;
  protected bit       exp_low_power_hint;

  // Everything the checker knows of that can legitimately make the device reset itself. A reset
  // the device performs with none of these standing is one nothing asked for.
  protected bit       cur_escalation;
  // The device has asked for the lifecycle reset and has not come back up yet. That reset is
  // what clears the fault status, so it is what ends the alert the fault status raises.
  protected bit       device_resetting;
  // Software has asked for an alert through `alert_test` and it has not been sent. A one shot: the
  // register pulses the sender, so this clears when the alert arrives rather than on a reset.
  protected int unsigned exp_alert_test;
  protected bit       cur_ndmreset;
  protected bit       cur_sw_rst_req;

  // What the testbench presents to the fast side, and what the device should record if it abandons
  // a low power transition. It gives up for the processor at one state and for a busy non-volatile
  // block at the next, so which it reports depends on what is true when it arrives. Kept with the
  // cycle each change was announced on: the device reads some through two flops, so a prediction
  // asks what the value was two cycles earlier.
  typedef struct {
    longint unsigned clk_count;
    bit              core_sleeping;
    bit              flash_idle;
    bit              otp_idle;
    bit              lc_idle;
  } pwrmgr_stim_seen_t;
  protected pwrmgr_stim_seen_t stim_history[$];
  protected bit       exp_fall_through;
  protected bit       exp_abort;

  // Whether the flag beside it rests on stimulus the device unambiguously saw. An input that moved
  // inside the crossing window could have been read either way, so the prediction is withdrawn
  // rather than guessed and the check it feeds stands down for that round.
  protected bit       exp_fall_through_known;
  protected bit       exp_abort_known;
  protected bit       cur_reset_req;

  // Set at low power entry and held until the device is running again. The interrupt is raised
  // because the device left low power for a wakeup, so one asserted before it got there counts too.

  protected wakeups_t exp_wake_status;
  protected wakeups_t exp_wake_info_reasons;
  protected bit       exp_intr_wakeup;

  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void reset(string kind = "HARD");

  extern virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);

  extern protected task process_aon_events();
  extern protected task process_fast_events();
  extern protected function void handle_wakeup(pwrmgr_wakeup_item item);
  extern protected function void evaluate_wake_cause();
  extern protected function void handle_active(pwrmgr_active_item item);
  extern protected function void handle_low_power(pwrmgr_flag_item item);
  extern protected function void handle_interrupt(pwrmgr_flag_item item);
  extern protected function void handle_fsm_state(pwrmgr_fsm_item item);
  extern protected function void record_stim(pwrmgr_fast_stim_item item);
  extern protected function pwrmgr_stim_seen_t stim_as_seen(longint unsigned at_count);
  extern protected function longint unsigned cycles_before(longint unsigned at_count,
                                                           int unsigned back);
  extern protected function void note_volatile_value(string name, bit [TL_DW-1:0] value);
  extern protected function void check_volatile_read(string name, bit [TL_DW-1:0] value);
  extern protected function void note_fault_status();
  extern protected function void sample_reset_coverage(bit sleep);
  extern protected function void sample_control_coverage(bit sleep);
  extern protected function void sample_rom_blocker_coverage();
  extern virtual function void on_alert(string alert_name, alert_esc_seq_item item);
endclass : pwrmgr_rst_safe_scoreboard


function void pwrmgr_rst_safe_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  wakeup_fifo    = new("wakeup_fifo", this);
  reset_req_fifo = new("reset_req_fifo", this);
  active_fifo    = new("active_fifo", this);
  low_power_fifo = new("low_power_fifo", this);
  intr_fifo      = new("intr_fifo", this);
  glitch_fifo    = new("glitch_fifo", this);
  esc_timeout_fifo = new("esc_timeout_fifo", this);
  stim_fifo      = new("stim_fifo", this);
  fsm_fifo       = new("fsm_fifo", this);
  clk_valid_fifo = new("clk_valid_fifo", this);
  aon_dir_fifo   = new("aon_dir_fifo", this);
  fast_dir_fifo  = new("fast_dir_fifo", this);
endfunction : build_phase


task pwrmgr_rst_safe_scoreboard::run_phase(uvm_phase phase);
  super.run_phase(phase);
  fork
    process_aon_events();
    process_fast_events();
  join_none
endtask : run_phase


function void pwrmgr_rst_safe_scoreboard::reset(string kind = "HARD");
  super.reset(kind);
  wakeup_fifo.flush();
  reset_req_fifo.flush();
  active_fifo.flush();
  low_power_fifo.flush();
  intr_fifo.flush();
  glitch_fifo.flush();
  esc_timeout_fifo.flush();
  stim_fifo.flush();
  cur_escalation  = 1'b0;
  device_resetting = 1'b0;
  exp_alert_test  = 0;

  // An alert owed before this reset is owed no longer, since the reset cleared the fault that asked
  // for it. A check already counting down cannot notice: it counts on a clock the device takes away
  // in reset and samples the reset flag only between those cycles. Lifted again by the next fault.
  ignore_exp_alert = 1'b1;
  cur_ndmreset    = 1'b0;
  cur_sw_rst_req  = 1'b0;
  fsm_fifo.flush();
  exp_fall_through  = 1'b0;
  exp_abort         = 1'b0;
  exp_fall_through_known = 1'b1;
  exp_abort_known        = 1'b1;
  stim_history.delete();
  clk_valid_fifo.flush();
  saw_invalid_state = 1'b0;
  saw_main_power_up = 1'b0;
  exp_fault_alert   = 1'b0;
  exp_fault_glitch  = 1'b0;
  exp_fault_esc_timeout = 1'b0;
  note_volatile_value("fault_status", '0);
  exp_fault_intg    = 1'b0;
  exp_ctrl_locked   = 1'b0;
  exp_low_power_hint = 1'b0;
  aon_dir_fifo.flush();
  fast_dir_fifo.flush();
  last_wakeup    = null;
  last_reset_req = null;
  last_active    = null;
  last_intr      = null;

  in_low_power          = 1'b0;
  record_en             = 1'b0;
  // The device clears its copy of the enable on the power-on reset, so nothing is enabled
  // again until software asks for the refresh.
  synced_wakeup_en      = '0;
  read_history.delete();
  update_count.delete();
  // The observation reports changes, so the value these come out of reset holding is never
  // published. A read taken before the first change still has to have something to match.
  note_volatile_value("wake_status", '0);
  note_volatile_value("wake_info_reasons", '0);
  cur_wakeups           = '0;
  cur_reset_req         = 1'b0;

  exp_wake_status       = '0;
  exp_wake_info_reasons = '0;
  exp_intr_wakeup       = 1'b0;
endfunction : reset


// The always-on side, in publication order.
task pwrmgr_rst_safe_scoreboard::process_aon_events();
  forever begin
    pwrmgr_aon_obs_kind_e kind;

    aon_dir_fifo.get(kind);
    `DV_CHECK_FATAL(!in_reset(),
                    "An always-on observation arrived while the power-on reset is asserted")

    case (kind)
      PwrmgrAonClkValid: begin
        pwrmgr_flag_item flag;
        `DV_CHECK_FATAL(clk_valid_fifo.try_get(flag),
                        "the direction stream named clk_valid with nothing published on it")
        cur_clk_running = flag.value;
        evaluate_wake_cause();
      end
      PwrmgrAonGlitch:   begin
        pwrmgr_flag_item flag;
        `DV_CHECK_FATAL(glitch_fifo.try_get(flag),
                        "the direction stream named glitch with nothing published on it")
        if (flag.value) saw_main_power_up = 1'b1;
        // The device records the glitch when the main power request stands while the system still
        // has its clock, so losing main power with the clock running is the whole cause.
        if (!flag.value && cur_clk_running) exp_fault_glitch = 1'b1;
        note_fault_status();
      end
      PwrmgrAonWakeup:   begin wakeup_fifo.get(last_wakeup); handle_wakeup(last_wakeup); end
      PwrmgrAonResetReq: begin
        `DV_CHECK_FATAL(reset_req_fifo.try_get(last_reset_req),
                        "the direction stream named reset_req with nothing published on it")
        cur_reset_req  = last_reset_req.rstreqs != '0;
        cur_escalation = last_reset_req.escalation;
        cur_sw_rst_req = last_reset_req.sw_rst_req == MuBi4True;
        // A reset makes the cause a reset rather than a wake, and the device raises no wakeup
        // interrupt for it.
        if (cur_reset_req) exp_intr_wakeup = 1'b0;
        evaluate_wake_cause();
        // The device is awake here: a reset request is what brought this announcement.
        sample_reset_coverage(.sleep(1'b0));
      end
      default: ;
    endcase
  end
endtask : process_aon_events


// The fast side, in publication order. Everything the device announces about one wake arrives
// here, so the order it arrives in is the order the device did it in.
task pwrmgr_rst_safe_scoreboard::process_fast_events();
  forever begin
    pwrmgr_fast_obs_kind_e kind;
    pwrmgr_flag_item       flag;

    fast_dir_fifo.get(kind);
    `DV_CHECK_FATAL(!in_reset(),
                    "A fast side observation arrived while the power-on reset is asserted")

    case (kind)
      PwrmgrFastActive:    begin active_fifo.get(last_active); handle_active(last_active); end
      PwrmgrFastLowPower:  begin low_power_fifo.get(flag); handle_low_power(flag); end
      PwrmgrFastIntr:      begin intr_fifo.get(flag); handle_interrupt(flag); end
      PwrmgrFastEscTimeout: begin
        pwrmgr_flag_item flag;
        `DV_CHECK_FATAL(esc_timeout_fifo.try_get(flag),
                        "the direction stream named esc_timeout with nothing published on it")
        // The monitor counts the escalation clock being away the same way the device does, so this
        // is the cause of the fault rather than a report of it.
        if (flag.value) exp_fault_esc_timeout = 1'b1;
        note_fault_status();
      end
      PwrmgrFastStim:      begin
        pwrmgr_fast_stim_item stim;
        `DV_CHECK_FATAL(stim_fifo.try_get(stim),
                        "the direction stream named stim with nothing published on it")
        record_stim(stim);
        cur_ndmreset      = stim.ndmreset_req;
      end
      PwrmgrFastFsmState:  begin
        pwrmgr_fsm_item fsm;
        `DV_CHECK_FATAL(fsm_fifo.try_get(fsm),
                        "the direction stream named fsm with nothing published on it")
        handle_fsm_state(fsm);
      end
      PwrmgrFastHwWrite:   ;
      PwrmgrFastPeerReq:   ;
      PwrmgrFastStrap:     ;
      default: ;
    endcase
  end
endtask : process_fast_events


// The status follows the sources asserted and enabled, so it drops when they are taken away. What
// was recorded about the wake is separate and accumulates.
function void pwrmgr_rst_safe_scoreboard::handle_wakeup(pwrmgr_wakeup_item item);
  cur_wakeups = item.wakeups;

  if (cfg.en_cov) begin
    foreach (cov.wakeup_ctrl_cg_wrap[i]) begin
      cov.wakeup_ctrl_cg_wrap[i].sample(synced_wakeup_en[i], !`gmv(ral.wake_info_capture_dis),
                                        cur_wakeups[i]);
    end
  end
  evaluate_wake_cause();
endfunction : handle_wakeup


// The control lock does not follow `low_power_o`, which resets asserted and would hold the register
// locked from the first cycle of every reset epoch. It follows `low_power_entry`.
function void pwrmgr_rst_safe_scoreboard::handle_low_power(pwrmgr_flag_item item);
  // Recording starts where low power does, unless software already suppressed it.
  if (item.value && !`gmv(ral.wake_info_capture_dis)) record_en = 1'b1;

  in_low_power = item.value;
  evaluate_wake_cause();

  // The other half of the same groups, taken where the device says it is asleep. A reset request
  // standing here would be the device contradicting itself rather than a case worth recording,
  // and the groups declare that pairing illegal, so the sample is left to the awake path.
  if (item.value && !cur_reset_req) sample_reset_coverage(.sleep(1'b1));
  if (item.value) sample_control_coverage(.sleep(1'b1));
endfunction : handle_low_power


function void pwrmgr_rst_safe_scoreboard::handle_interrupt(pwrmgr_flag_item item);
  last_intr = item;
  if (!item.value) return;
  // The register tests stand the scoreboard down. The framework honours that on the paths it owns;
  // this one is reached from the device's announcement rather than from a transaction.
  if (!cfg.en_scb) return;

  `DV_CHECK_EQ(exp_intr_wakeup, 1'b1,
               "The device raised the wakeup interrupt with no wakeup to account for it")
  `DV_CHECK_EQ(`gmv(ral.intr_enable.wakeup), 1'b1,
               "The device raised the wakeup interrupt while it was disabled")
endfunction : handle_interrupt




// The cause is decided from levels, not edges: a source already asserted before the device went
// down counts and announces no change, so this is evaluated at every event that can move either
// term. A reset request outranks a wake.
function void pwrmgr_rst_safe_scoreboard::sample_control_coverage(bit sleep);
  control_enables_t enables;

  if (!cfg.en_cov) return;

% for clk in src_clks:
  % if clk == 'usb':
  enables.usb_clk_en_lp     = bit'(`gmv(ral.control.usb_clk_en_lp));
  enables.usb_clk_en_active = bit'(`gmv(ral.control.usb_clk_en_active));
  % else:
<% clk_core = 'core' if clk == 'main' else clk %>\
  enables.${clk}_clk_en = bit'(`gmv(ral.control.${clk_core}_clk_en));
  % endif
% endfor
  enables.main_pd_n = bit'(`gmv(ral.control.main_pd_n));

  cov.control_cg.sample(enables, sleep);
endfunction : sample_control_coverage


// The rom and lifecycle inputs that hold the device short of active. These are driven and held by
// the testbench rather than produced by the device, so taking them at a device announcement is a
// read of settled stimulus rather than a race against an output.
function void pwrmgr_rst_safe_scoreboard::sample_rom_blocker_coverage();
  if (!cfg.en_cov) return;

  cov.rom_active_blockers_cg.sample(
% for r in range(NumRomInputs):
      cfg.pwrmgr_vif.rom_ctrl_i[${r}].done,
      cfg.pwrmgr_vif.rom_ctrl_i[${r}].good,
% endfor
      cfg.pwrmgr_vif.lc_dft_en,
      cfg.pwrmgr_vif.lc_hw_debug_en);
endfunction : sample_rom_blocker_coverage


// Takes every reset group at one moment, so the bins describe one consistent view of the device
// rather than several taken at different times.
function void pwrmgr_rst_safe_scoreboard::sample_reset_coverage(bit sleep);
  resets_t resets_en;

  if (!cfg.en_cov) return;

  resets_en = resets_t'(`gmv(ral.reset_en));
  cov.hw_reset_0_cg.sample(last_reset_req.rstreqs[0], resets_en[0], sleep);
  cov.hw_reset_1_cg.sample(last_reset_req.rstreqs[1], resets_en[1], sleep);
  cov.rstmgr_sw_reset_cg.sample(cur_sw_rst_req);
  cov.main_power_reset_cg.sample(saw_main_power_up ? 1'b0 : 1'b1, sleep);
  cov.esc_reset_cg.sample(cur_escalation, sleep);
endfunction : sample_reset_coverage


function void pwrmgr_rst_safe_scoreboard::evaluate_wake_cause();
  wakeups_t enabled = cur_wakeups & synced_wakeup_en;

  // The status follows the sources as they stand, so it drops again when they are taken away.
  exp_wake_status = enabled;
  note_volatile_value("wake_status", exp_wake_status);

  // What is recorded accumulates while the device is recording and holds a source that has since
  // gone. It is taken from the level on each fast clock edge, so nothing is recorded while the
  // clock is stopped.
  if (record_en && cur_clk_running) exp_wake_info_reasons |= enabled;
  note_volatile_value("wake_info_reasons", exp_wake_info_reasons);

  if (in_low_power && enabled != '0 && !cur_reset_req) exp_intr_wakeup = 1'b1;

  if (cfg.en_cov) begin
    bit enable = bit'(`gmv(ral.intr_enable.wakeup));
    foreach (cov.wakeup_intr_cg_wrap[i]) begin
      cov.wakeup_intr_cg_wrap[i].sample(enable, exp_intr_wakeup, exp_wake_status[i],
                                        exp_intr_wakeup && enable);
    end
  end
endfunction : evaluate_wake_cause


// Each value these registers are seen to hold, so a read can be answered against the values live
// around it rather than one instant.
// The fault status is the three predicted causes in register order. The bits are sticky, and it is
// recorded when a cause is predicted because the device records slightly after the announcement, so
// a read in that window may return either value.
function void pwrmgr_rst_safe_scoreboard::note_fault_status();
  note_volatile_value("fault_status", {exp_fault_glitch, exp_fault_esc_timeout, exp_fault_intg});

  // The alert is declared where a cause is predicted, being exactly the or of the three fault bits,
  // so the first cause raises it. Declaring it again on a later cause would open a fresh window for
  // an alert already sent.
  if ((exp_fault_glitch || exp_fault_esc_timeout || exp_fault_intg) && !exp_fault_alert) begin
    exp_fault_alert  = 1'b1;
    // A fresh cause, so the alert is owed again and the framework is told to hold this one to
    // account. This is what bounds the window opened when the device's reset withdrew the last one.
    ignore_exp_alert = 1'b0;
    set_exp_alert("fatal_fault", .is_fatal(1'b0), .max_delay(FatalAlertMaxDelay));
  end
endfunction : note_fault_status


// An alert is accounted for by a predicted fault, not by an expectation the framework has spent:
// the device re-sends while the fault status stands, and the framework clears its flag on the first
// handshake.
// It is declared not fatal because the causes all reset the lifecycle domain, where the fault
// status lives, so the device silences its own alert rather than sending until the reset.
function void pwrmgr_rst_safe_scoreboard::on_alert(string alert_name, alert_esc_seq_item item);
  if (do_alert_check && cfg.en_scb) begin
    `DV_CHECK_EQ(exp_fault_alert || (exp_alert_test > 0), 1'b1,
                 "the device sent its fatal alert with nothing to account for it")
  end
  // Each `alert_test` write buys one alert and several can be outstanding, so they are counted. An
  // alert with none owed and no fault predicted is still a defect.
  if (exp_alert_test > 0) exp_alert_test--;
endfunction : on_alert


function void pwrmgr_rst_safe_scoreboard::note_volatile_value(string name,
                                                              bit [TL_DW-1:0] value);
  volatile_update_t upd;

  update_count[name] = update_count.exists(name) ? update_count[name] + 1 : 1;
  upd.index = update_count[name];
  upd.value = value;
  read_history[name].push_back(upd);
  while (read_history[name].size() > VolatileReadHistoryDepth) begin
    void'(read_history[name].pop_front());
  end
endfunction : note_volatile_value


// A read of a hardware written register is answered at the instant the bus takes it, and the value
// can move either side of that, so it is checked against the values it is known to have held.
// Newest first, since a value recurs.
function void pwrmgr_rst_safe_scoreboard::check_volatile_read(string name,
                                                              bit [TL_DW-1:0] value);
  for (int i = read_history[name].size() - 1; i >= 0; i--) begin
    if (read_history[name][i].value == value) return;
  end

  `uvm_error(`gfn, $sformatf(
             "read mismatch on %0s: 0x%0h is not among the last %0d values it held, %p",
             name, value, VolatileReadHistoryDepth, read_history[name]))
endfunction : check_volatile_read


// The state machine wedges when corrupted and only a reset takes it out, which is the property the
// invalid state tests check.
// Step back a number of cycles without running off the start of the run.
function longint unsigned pwrmgr_rst_safe_scoreboard::cycles_before(longint unsigned at_count,
                                                                   int unsigned back);
  return (at_count > back) ? (at_count - back) : 0;
endfunction : cycles_before


// Keep what was driven, with the cycle it changed on. A pin holds its value between changes, so
// the entry that is in effect at any cycle is the newest one at or before it.
function void pwrmgr_rst_safe_scoreboard::record_stim(pwrmgr_fast_stim_item item);
  pwrmgr_stim_seen_t entry;

  entry.clk_count     = item.clk_count;
  entry.core_sleeping = item.core_sleeping;
  entry.flash_idle    = item.flash_idle;
  entry.otp_idle      = item.otp_idle;
  entry.lc_idle       = item.lc_idle;
  stim_history.push_back(entry);
  while (stim_history.size() > StimHistoryDepth) void'(stim_history.pop_front());
endfunction : record_stim


// What was being driven at a given cycle. Before anything is driven the answer is the state the
// device is released into: the processor running and every block idle.
function pwrmgr_rst_safe_scoreboard::pwrmgr_stim_seen_t
    pwrmgr_rst_safe_scoreboard::stim_as_seen(longint unsigned at_count);
  pwrmgr_stim_seen_t answer;

  answer = '{clk_count: 0, core_sleeping: 1'b0, flash_idle: 1'b1, otp_idle: 1'b1, lc_idle: 1'b1};
  foreach (stim_history[i]) begin
    if (stim_history[i].clk_count <= at_count) answer = stim_history[i];
  end
  return answer;
endfunction : stim_as_seen


function void pwrmgr_rst_safe_scoreboard::handle_fsm_state(pwrmgr_fsm_item item);
  // The fall through also needs the hint, and has to be evaluated before the device clears it in
  // this same state.
  if (item.state inside {pwrmgr_pkg::FastPwrStateRomCheckDone,
                         pwrmgr_pkg::FastPwrStateRomCheckGood}) begin
    sample_rom_blocker_coverage();
  end

  if (item.state == pwrmgr_pkg::FastPwrStateFallThrough) begin
    pwrmgr_stim_seen_t late  = stim_as_seen(cycles_before(item.clk_count, SyncFlops));
    pwrmgr_stim_seen_t early = stim_as_seen(cycles_before(item.clk_count,
                                                          SyncFlops + CdcJitterCycles));
    exp_fall_through_known = (early.core_sleeping == late.core_sleeping);
    exp_fall_through       = !(late.core_sleeping && exp_low_power_hint);
  end
  if (item.state == pwrmgr_pkg::FastPwrStateNvmIdleChk) begin
    pwrmgr_stim_seen_t late   = stim_as_seen(cycles_before(item.clk_count, SyncFlops));
    pwrmgr_stim_seen_t early  = stim_as_seen(cycles_before(item.clk_count,
                                                           SyncFlops + CdcJitterCycles));
    // The lifecycle idle has no flops in its path, so it is read at the state itself and has no
    // window of its own.
    pwrmgr_stim_seen_t direct = stim_as_seen(item.clk_count);
    exp_abort_known = (early.otp_idle == late.otp_idle) && (early.flash_idle == late.flash_idle);
    exp_abort       = !(late.otp_idle && direct.lc_idle && late.flash_idle);
  end

  // `wkup_o` is asserted unconditionally on both paths that abandon a transition, so the interrupt
  // follows the two predictions above and not only the wakeup sources.
  if (exp_fall_through || exp_abort) exp_intr_wakeup = 1'b1;

  // The device clears the low power hint itself when it asks whether the processor is still
  // sleeping. Held beside the mirror, because it can clear part way through a software access.
  if (item.state == pwrmgr_pkg::FastPwrStateFallThrough) exp_low_power_hint = 1'b0;

  // The control register lock. The device closes it on `low_power_entry`, which is also what takes
  // the state machine out of the active state; a reset request leaves that state without closing
  // the lock, so the condition is asked rather than the state.
  //
  // Leaving the active state also begins a new attempt, so both abandonment predictions start again
  // here. Otherwise a round the processor abandons is compared against an earlier round's abort.
  if (item.state == pwrmgr_pkg::FastPwrStateDisClks) begin
    pwrmgr_stim_seen_t synced = stim_as_seen(cycles_before(item.clk_count, SyncFlops));
    if (synced.core_sleeping && exp_low_power_hint) exp_ctrl_locked = 1'b1;
    exp_fall_through = 1'b0;
    exp_abort        = 1'b0;
    // A fresh attempt starts from a settled prediction.
    exp_fall_through_known = 1'b1;
    exp_abort_known        = 1'b1;
  end

  // It opens again on either of the two things the device does it for, each landing one state after
  // the condition holds.
  if (item.state inside {pwrmgr_pkg::FastPwrStateStrap, pwrmgr_pkg::FastPwrStateRomCheckDone}) begin
    exp_ctrl_locked = 1'b0;
  end

  // The device asks for the lifecycle reset in `FastPwrStateResetPrep` and holds it through
  // `FastPwrStateResetWait`. The fault status lives in that reset's domain, so the bits and the
  // alert they raised are gone by `FastPwrStateLowPower`. Asked in two steps because an ordinary
  // low power entry also ends there and resets nothing.
  if (item.state inside {pwrmgr_pkg::FastPwrStateResetPrep,
                         pwrmgr_pkg::FastPwrStateResetWait}) begin
    device_resetting = 1'b1;
  end
  if (item.state == pwrmgr_pkg::FastPwrStateLowPower && device_resetting) begin
    device_resetting      = 1'b0;
    exp_fault_alert       = 1'b0;
    exp_fault_glitch      = 1'b0;
    exp_fault_esc_timeout = 1'b0;
    exp_fault_intg        = 1'b0;
    note_volatile_value("fault_status", '0);
    // The interrupt goes the same way as the fault status: the device's own reset clears it whether
    // or not software asked. Only a write of one, or the power-on reset, cleared this before.
    exp_intr_wakeup       = 1'b0;

    // An alert that was owed is owed no longer, since the device's own reset cleared the fault.
    // Without this the wait would run out and be reported as a failure to alert. It applies only to
    // an alert declared not fatal, and is lifted when a new fault is predicted.
    ignore_exp_alert      = 1'b1;
  end

  if (item.state == pwrmgr_pkg::FastPwrStateInvalid) begin
    // No alert is expected here. The device raises its fatal alert for a register integrity error,
    // an escalation timeout and a main power glitch; every other fault is answered with a reset
    // alone.
    saw_invalid_state = 1'b1;
    return;
  end

  `DV_CHECK_EQ(saw_invalid_state, 1'b0,
               "the device left its invalid state without a reset")
endfunction : handle_fsm_state




// The device reporting that the processor may run is where what it recorded is complete.
function void pwrmgr_rst_safe_scoreboard::handle_active(pwrmgr_active_item item);
endfunction : handle_active


// Register traffic. A write is predicted when issued; a read is compared against the mirror unless
// the hardware writes the register, in which case it is checked against the reference model below.
task pwrmgr_rst_safe_scoreboard::process_tl_access(tl_seq_item item, tl_channels_e channel,
                                                   string ral_name);
  uvm_reg        csr;
  bit            write = item.is_write();
  uvm_reg_addr_t csr_addr = cfg.ral_models[ral_name].get_word_aligned_addr(item.a_addr);
  bit            addr_phase_write = (write && channel == AddrChannel);
  bit            data_phase_write = (write && channel == DataChannel);
  bit            data_phase_read = (!write && channel == DataChannel);
  bit            do_read_check = 1'b1;

  if (!(csr_addr inside {cfg.ral_models[ral_name].csr_addrs})) begin
    `uvm_fatal(`gfn, $sformatf("Access to an address with no register: 0x%0h", csr_addr))
  end
  csr = cfg.ral_models[ral_name].default_map.get_reg_by_offset(csr_addr);
  `DV_CHECK_NE_FATAL(csr, null)

  // This block does not call super::process_tl_access, following the same convention gpio and dma
  // do, so the framework's own check of this flag never runs here and it is checked directly.
  if (!cfg.en_scb) return;

  // A transaction with bad command integrity is what makes the device record an integrity fault, so
  // the fault and its alert are predicted from that transaction.
  if (channel == AddrChannel && !item.is_a_chan_intg_ok(.throw_error(0))) begin
    exp_fault_intg = 1'b1;
    note_fault_status();
    update_tl_alert_field_prediction();
  end

  // A write while the device holds the lock changes nothing, so the model must not follow it
  // either: a drifted mirror would judge every later read against a value software never wrote.
  if (addr_phase_write && csr.get_name() == "control" && !exp_ctrl_locked) begin
    exp_low_power_hint = bit'(get_field_val(ral.control.low_power_hint, item.a_data));
  // The processor is running to have issued this write.
  sample_control_coverage(.sleep(1'b0));
  end

  if (addr_phase_write && !(csr.get_name() == "control" && exp_ctrl_locked)) begin
    void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));
  end

  case (csr.get_name())
    // Written by hardware, so a read is compared against what the model expects rather than
    // against the mirror.
    "wake_info": begin
      // Checked against the values the register held rather than the running model: the sources
      // arrive through two synchronizers and a slower clock domain, so the model has a change in
      // hand before the device can have taken it. The two flags are compared exactly, being settled
      // long before a test reads them.
      if (data_phase_read) begin
        check_volatile_read("wake_info_reasons",
                            wakeups_t'(get_field_val(ral.wake_info.reasons, item.d_data)));
        if (exp_fall_through_known) begin
          `DV_CHECK_EQ(bit'(get_field_val(ral.wake_info.fall_through, item.d_data)),
                       exp_fall_through,
                       "the device recorded abandoning for the processor when it did not")
        end else begin
          `uvm_info(`gfn, "fall through unchecked: the processor moved inside the crossing window",
                    UVM_MEDIUM)
        end
        if (exp_abort_known) begin
          `DV_CHECK_EQ(bit'(get_field_val(ral.wake_info.abort, item.d_data)), exp_abort,
                       "the device recorded abandoning for a busy block when it did not")
        end else begin
          `uvm_info(`gfn, "abort unchecked: a block moved inside the crossing window", UVM_MEDIUM)
        end
      end
      // A write clears the bits it names whatever the recording is doing: the clear is taken ahead
      // of the accumulation, so it needs no quiet window.
      if (data_phase_write) begin
        exp_wake_info_reasons &= ~wakeups_t'(get_field_val(ral.wake_info.reasons, item.a_data));
        note_volatile_value("wake_info_reasons", exp_wake_info_reasons);
        // The whole register clears on a write of one, not just the reasons. A model that cleared
        // only the reasons kept the flags and disagreed with every later read.
        if (get_field_val(ral.wake_info.fall_through, item.a_data)) exp_fall_through = 1'b0;
        if (get_field_val(ral.wake_info.abort, item.a_data)) exp_abort = 1'b0;
      end
      do_read_check = 1'b0;
    end
    "intr_state": begin
      if (data_phase_read) begin
        `DV_CHECK_EQ(bit'(get_field_val(ral.intr_state.wakeup, item.d_data)), exp_intr_wakeup,
                     "intr_state wakeup does not match the expected value")
      end
      // Write one to clear.
      if (data_phase_write && get_field_val(ral.intr_state.wakeup, item.a_data)) begin
        exp_intr_wakeup = 1'b0;
      end
      do_read_check = 1'b0;
    end
    "ctrl_cfg_regwen": begin
      if (data_phase_read) begin
        `DV_CHECK_EQ(bit'(item.d_data[0]), !exp_ctrl_locked,
                     "the device reported its control register lock in the wrong state")
      end
      do_read_check = 1'b0;
    end
    "wake_status": begin
      // Live: it follows the sources as they stand, and the checker learns of a change through
      // a separate observation, so the read is checked against the values it held.
      if (data_phase_read) check_volatile_read("wake_status", item.d_data);
      do_read_check = 1'b0;
    end
    // Every bit but the hint is software's, so the mirror answers for them. The hint is the
    // device's to clear, so it is compared against what the device was last seen to do.
    "control": begin
      if (data_phase_read) begin
        uvm_reg_data_t hint_mask = ((1 << ral.control.low_power_hint.get_n_bits()) - 1)
                                   << ral.control.low_power_hint.get_lsb_pos();
        `DV_CHECK_EQ(bit'(get_field_val(ral.control.low_power_hint, item.d_data)),
                     exp_low_power_hint,
                     "the low power hint read back a value the device had not left there")
        `DV_CHECK_EQ(item.d_data & ~hint_mask, csr.get_mirrored_value() & ~hint_mask,
                     "the control register read back a value it was not written")
      end
      do_read_check = 1'b0;
    end
    // Predicted from the three causes rather than read out of the device, so a fault the device
    // records without one, or fails to record when one happened, is reportable.
    "fault_status": begin
      if (data_phase_read) check_volatile_read("fault_status", item.d_data);
      do_read_check = 1'b0;
    end
    "reset_status", "escalate_reset_status": begin
      do_read_check = 1'b0;
    end
    // Write only, or self clearing, so a read tells nothing about what was written. Writing this
    // raises the interrupt the same way a wakeup does: `prim_intr_hw` takes the written bit
    // alongside the event, so it is a cause and has to be predicted as one.
    "intr_test": begin
      // Predicted when the write is taken, not when it is answered. The device acts on the write
      // enable as the transfer is accepted and announces the interrupt on its own stream, so
      // predicting on the answer leaves a window where the interrupt is announced and nothing
      // accounts for it.
      if (addr_phase_write && get_field_val(ral.intr_test.wakeup, item.a_data)) begin
        exp_intr_wakeup = 1'b1;
      end
      do_read_check = 1'b0;
    end
    // Writing this sends an alert with no fault behind it: the written bit goes straight to
    // `prim_alert_sender` as `alert_test_i`, so the alert is accounted for by the write.
    "alert_test": begin
      // Taken at the same point and for the same reason as the interrupt test above.
      if (addr_phase_write && get_field_val(ral.alert_test.fatal_fault, item.a_data)) begin
        exp_alert_test++;
        set_exp_alert("fatal_fault", .is_fatal(1'b0), .max_delay(FatalAlertMaxDelay));
      end
      do_read_check = 1'b0;
    end
    // Asking for the refresh is what puts the enable software wrote into the copy the device
    // works from. Until this happens the device keeps using the copy it already had.
    "cfg_cdc_sync": begin
      if (data_phase_write && item.a_data[0]) begin
        synced_wakeup_en = wakeups_t'(`gmv(ral.wakeup_en[0]));
        evaluate_wake_cause();
      end
      do_read_check = 1'b0;
    end
    "wake_info_capture_dis": begin
      // Software disabling capture stops the recording that was under way.
      if (data_phase_write && item.a_data[0]) record_en = 1'b0;
    end
    default: ;
  endcase

  if (data_phase_read) begin
    if (do_read_check) begin
      `DV_CHECK_EQ(csr.get_mirrored_value(), item.d_data,
                   $sformatf("register %0s read back a value it was not written",
                             csr.get_full_name()))
    end
    void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));
  end
endtask : process_tl_access
