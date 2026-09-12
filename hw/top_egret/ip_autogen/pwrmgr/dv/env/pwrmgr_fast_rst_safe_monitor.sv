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
  uvm_analysis_port #(pwrmgr_fast_obs_kind_e) fast_dir_port;

  protected bit                       have_previous;
  protected lc_ctrl_pkg::lc_tx_t      prev_fetch_en;
  protected logic                     prev_low_power;
  protected logic                     prev_strap;
  protected logic                     prev_intr_wakeup;
  protected pwrmgr_pkg::pwr_rst_req_t prev_rst_req;
  protected pwrmgr_pkg::pwr_clk_req_t prev_clk_req;
  protected lc_ctrl_pkg::pwr_lc_req_t prev_lc_req;
  protected pwrmgr_pkg::pwr_otp_req_t prev_otp_req;

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
  forever begin
    lc_ctrl_pkg::lc_tx_t      fetch_en;
    logic                     low_power, strap, intr_wakeup;
    pwrmgr_pkg::pwr_rst_req_t rst_req;
    pwrmgr_pkg::pwr_clk_req_t clk_req;
    lc_ctrl_pkg::pwr_lc_req_t lc_req;
    pwrmgr_pkg::pwr_otp_req_t otp_req;
    longint unsigned          clk_count;

    @(posedge cfg.vif.clk);

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
  have_previous = 1'b0;
endfunction : reset_monitor
