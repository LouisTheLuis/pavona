// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Passive observation of the fast side of the device.
//
// One collector runs for the reset epoch, publishing a named event each time one of the things
// it watches changes and naming that publication on the direction port.
class pwrmgr_fast_rst_safe_monitor extends dv_rst_safe_base_monitor #(
    .ITEM_T    (pwrmgr_active_item),
    .REQ_ITEM_T(pwrmgr_fast_item),
    .RSP_ITEM_T(pwrmgr_fast_item),
    .CFG_T     (pwrmgr_fast_agent_cfg),
    .COV_T     (dv_base_agent_cov)
  );

  `uvm_component_utils(pwrmgr_fast_rst_safe_monitor)
  `uvm_component_new

  // The device announcing that the processor may run. This is what a sequence waits for before
  // touching a register after a reset.
  uvm_analysis_port #(pwrmgr_active_item)    active_port;
  uvm_analysis_port #(pwrmgr_flag_item)      low_power_port;
  uvm_analysis_port #(pwrmgr_flag_item)      strap_port;
  uvm_analysis_port #(pwrmgr_flag_item)      intr_port;
  uvm_analysis_port #(pwrmgr_peer_req_item)  peer_req_port;
  uvm_analysis_port #(pwrmgr_flag_item)       esc_timeout_port;
  uvm_analysis_port #(pwrmgr_fast_stim_item)  stim_port;
  uvm_analysis_port #(pwrmgr_fsm_item)        fsm_port;
  uvm_analysis_port #(pwrmgr_fast_obs_kind_e) fast_dir_port;

  // Registers the device wrote itself, published when the committed value changes.

  protected bit                          have_previous;
  protected bit                          prev_ndmreset_req;
  protected bit                          prev_core_sleeping;
  protected bit                          prev_flash_idle;
  protected bit                          prev_otp_idle;
  protected bit                          prev_lc_idle;
  protected pwrmgr_pkg::fast_pwr_state_e prev_fsm_state;
  protected lc_ctrl_pkg::lc_tx_t         prev_fetch_en;
  protected logic                        prev_low_power;
  protected logic                        prev_strap;
  protected logic                        prev_intr_wakeup;
  protected pwrmgr_pkg::pwr_rst_req_t    prev_rst_req;
  protected pwrmgr_pkg::pwr_clk_req_t    prev_clk_req;
  protected lc_ctrl_pkg::pwr_lc_req_t    prev_lc_req;
  protected pwrmgr_pkg::pwr_otp_req_t    prev_otp_req;

  // How long the escalation path has been unusable, and whether that has already been reported.
  // The device gives up on it after a set number of cycles, so counting them is what turns a
  // broken clock into an event the checker can act on.
  protected int unsigned esc_broken_cycles;
  protected bit          esc_timeout_reported;

  // Escalation clock cycles seen since the clock was last given back. The device's count survives
  // an interruption and is cleared by an acknowledgment that has to cross into this clock domain
  // and back, so this is what says the clock has been there long enough for that to have happened.
  protected int unsigned esc_running_cycles;

  extern function void build_phase(uvm_phase phase);
  extern virtual task collect_trans();
  extern virtual function void reset_monitor();
  extern protected function void publish_flag(uvm_analysis_port #(pwrmgr_flag_item) port,
                                              pwrmgr_fast_obs_kind_e kind, logic value,
                                              longint unsigned clk_count);
endclass : pwrmgr_fast_rst_safe_monitor


function void pwrmgr_fast_rst_safe_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  active_port    = new("active_port", this);
  low_power_port = new("low_power_port", this);
  strap_port     = new("strap_port", this);
  intr_port      = new("intr_port", this);
  peer_req_port  = new("peer_req_port", this);
  esc_timeout_port = new("esc_timeout_port", this);
  stim_port      = new("stim_port", this);
  fsm_port       = new("fsm_port", this);
  fast_dir_port  = new("fast_dir_port", this);
endfunction : build_phase


function void pwrmgr_fast_rst_safe_monitor::publish_flag(
    uvm_analysis_port #(pwrmgr_flag_item) port, pwrmgr_fast_obs_kind_e kind, logic value,
    longint unsigned clk_count);
  pwrmgr_flag_item item = pwrmgr_flag_item::type_id::create("flag_item");
  item.value     = value;
  item.clk_count = clk_count;
  port.write(item);
  fast_dir_port.write(kind);
endfunction : publish_flag


task pwrmgr_fast_rst_safe_monitor::collect_trans();
  fork
    forever begin
      @(posedge cfg.esc_clk_rst_vif.clk);
      if (esc_running_cycles < EscTimeoutAckCycles) esc_running_cycles++;
    end
  join_none

  forever begin
    pwrmgr_pkg::fast_pwr_state_e fsm_state;
    lc_ctrl_pkg::lc_tx_t         fetch_en;
    logic                        low_power, strap, intr_wakeup;
    pwrmgr_pkg::pwr_rst_req_t    rst_req;
    pwrmgr_pkg::pwr_clk_req_t    clk_req;
    lc_ctrl_pkg::pwr_lc_req_t    lc_req;
    pwrmgr_pkg::pwr_otp_req_t    otp_req;
    longint unsigned             clk_count;

    @(posedge cfg.vif.clk);

    fsm_state   = cfg.vif.fast_state;
    fetch_en    = cfg.vif.fetch_en;
    low_power   = cfg.vif.low_power;
    strap       = cfg.vif.strap;
    intr_wakeup = cfg.vif.intr_wakeup;
    rst_req     = cfg.vif.pwr_rst_req;
    clk_req     = cfg.vif.pwr_clk_req;
    lc_req      = cfg.vif.pwr_lc_req;
    otp_req     = cfg.vif.pwr_otp_req;
    clk_count   = cfg.reset_domain.clk_rst_vif.posedge_count;

    if (!have_previous || fetch_en !== prev_fetch_en) begin
      pwrmgr_active_item item = pwrmgr_active_item::type_id::create("active_item");
      item.fetch_en  = fetch_en;
      item.clk_count = clk_count;
      active_port.write(item);
      fast_dir_port.write(PwrmgrFastActive);
    end

    // The device only counts while it has asked for an ip clock: `u_esc_timeout` is enabled by
    // `|pwr_clk_o`, so it holds at zero through a low power window however long the escalation
    // clock is away. Counting regardless would announce a timeout the device never reaches.
    //
    // The clock being back does not by itself clear the count. The device clears on an
    // acknowledgment that crosses into the escalation domain and back, so a clock returned for less
    // than that round trip leaves the count where the interruption left it, and two interruptions
    // close together are one outage to the device.
    if (cfg.esc_clk_rst_vif.clk_gate || cfg.esc_clk_rst_vif.rst_n === 1'b0) begin
      esc_running_cycles = 0;
      if (clk_req != '0) begin
        esc_broken_cycles++;
        if (esc_broken_cycles >= EscTimeoutDetectCycles && !esc_timeout_reported) begin
          pwrmgr_flag_item item = pwrmgr_flag_item::type_id::create("esc_timeout_item");
          item.value           = 1'b1;
          item.clk_count       = cfg.reset_domain.clk_rst_vif.posedge_count;
          esc_timeout_reported = 1'b1;
          esc_timeout_port.write(item);
          fast_dir_port.write(PwrmgrFastEscTimeout);
        end
      end
    end else if (clk_req == '0 || esc_running_cycles >= EscTimeoutAckCycles) begin
      // Losing the ip clock request clears the device's counter outright, through `en_i`, with no
      // acknowledgment needed.
      esc_broken_cycles    = 0;
      esc_timeout_reported = 1'b0;
    end

    if (!have_previous ||
        cfg.vif.cpu_i.ndmreset_req !== prev_ndmreset_req ||
        cfg.vif.pwr_cpu.core_sleeping !== prev_core_sleeping ||
        cfg.vif.pwr_flash.flash_idle !== prev_flash_idle ||
        cfg.vif.pwr_otp_rsp.otp_idle !== prev_otp_idle ||
        cfg.vif.pwr_lc_rsp.lc_idle !== prev_lc_idle) begin
      pwrmgr_fast_stim_item item = pwrmgr_fast_stim_item::type_id::create("stim_item");
      item.ndmreset_req  = cfg.vif.cpu_i.ndmreset_req;
      item.core_sleeping = cfg.vif.pwr_cpu.core_sleeping;
      item.flash_idle    = cfg.vif.pwr_flash.flash_idle;
      item.otp_idle      = cfg.vif.pwr_otp_rsp.otp_idle;
      item.lc_idle       = cfg.vif.pwr_lc_rsp.lc_idle;
      item.clk_count     = cfg.reset_domain.clk_rst_vif.posedge_count;
      prev_ndmreset_req  = item.ndmreset_req;
      prev_core_sleeping = item.core_sleeping;
      prev_flash_idle    = item.flash_idle;
      prev_otp_idle      = item.otp_idle;
      prev_lc_idle       = item.lc_idle;
      stim_port.write(item);
      fast_dir_port.write(PwrmgrFastStim);
    end

    if (!have_previous || fsm_state !== prev_fsm_state) begin
      pwrmgr_fsm_item item = pwrmgr_fsm_item::type_id::create("fsm_item");
      item.state     = fsm_state;
      item.clk_count = cfg.reset_domain.clk_rst_vif.posedge_count;
      fsm_port.write(item);
      fast_dir_port.write(PwrmgrFastFsmState);
    end

    if (!have_previous || low_power !== prev_low_power) begin
      publish_flag(low_power_port, PwrmgrFastLowPower, low_power, clk_count);
    end
    if (!have_previous || strap !== prev_strap) begin
      publish_flag(strap_port, PwrmgrFastStrap, strap, clk_count);
    end
    if (!have_previous || intr_wakeup !== prev_intr_wakeup) begin
      publish_flag(intr_port, PwrmgrFastIntr, intr_wakeup, clk_count);
    end

    if (!have_previous || rst_req !== prev_rst_req || clk_req !== prev_clk_req ||
        lc_req !== prev_lc_req || otp_req !== prev_otp_req) begin
      pwrmgr_peer_req_item item = pwrmgr_peer_req_item::type_id::create("peer_req_item");
      item.rst_req   = rst_req;
      item.clk_req   = clk_req;
      item.lc_req    = lc_req;
      item.otp_req   = otp_req;
      item.clk_count = clk_count;
      peer_req_port.write(item);
      fast_dir_port.write(PwrmgrFastPeerReq);
    end

    prev_fsm_state   = fsm_state;
    prev_fetch_en    = fetch_en;
    prev_low_power   = low_power;
    prev_strap       = strap;
    prev_intr_wakeup = intr_wakeup;
    prev_rst_req     = rst_req;
    prev_clk_req     = clk_req;
    prev_lc_req      = lc_req;
    prev_otp_req     = otp_req;
    have_previous    = 1'b1;
  end
endtask : collect_trans


function void pwrmgr_fast_rst_safe_monitor::reset_monitor();
  esc_broken_cycles    = 0;
  esc_timeout_reported = 1'b0;
  esc_running_cycles   = 0;
  have_previous    = 1'b0;
endfunction : reset_monitor
