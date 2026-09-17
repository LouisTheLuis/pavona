// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Passive observation of the always-on side of the device.
//
// One collector runs for the reset epoch. It publishes a named event each time one of the things
// it watches changes, and names that publication on the direction port so a consumer can order
// events that arrived on different ports.
class pwrmgr_aon_rst_safe_monitor extends dv_rst_safe_base_monitor #(
    .ITEM_T    (pwrmgr_wakeup_item),
    // The inherited request and response ports are wired to the sequencer by the base agent, so
    // they carry the item the sequencer deals in. Observations go out on the ports below.
    .REQ_ITEM_T(pwrmgr_aon_item),
    .RSP_ITEM_T(pwrmgr_aon_item),
    .CFG_T     (pwrmgr_aon_agent_cfg),
    .COV_T     (dv_base_agent_cov)
  );

  `uvm_component_utils(pwrmgr_aon_rst_safe_monitor)
  `uvm_component_new

  uvm_analysis_port #(pwrmgr_wakeup_item)         wakeup_port;
  uvm_analysis_port #(pwrmgr_reset_req_item)      reset_req_port;
  uvm_analysis_port #(pwrmgr_ast_req_item)        ast_req_port;
  uvm_analysis_port #(pwrmgr_flag_item)           glitch_port;
  uvm_analysis_port #(pwrmgr_flag_item)           clk_valid_port;
  uvm_analysis_port #(pwrmgr_aon_obs_kind_e)      aon_dir_port;

  // Previous values, used only to decide what changed. Cleared at reset so the first sample of
  // a new epoch republishes everything.
  protected bit                       have_previous;
  protected wakeups_t                 prev_wakeups;
  protected resets_t                  prev_rstreqs;
  protected mubi4_t                   prev_sw_rst_req;
  protected bit                       prev_escalation;
  protected pwrmgr_pkg::pwr_ast_req_t prev_ast_req;
  protected logic                     prev_main_pwr_ok;
  protected logic                     prev_io_clk_val;

  extern function void build_phase(uvm_phase phase);
  extern virtual task collect_trans();
  extern virtual function void reset_monitor();
endclass : pwrmgr_aon_rst_safe_monitor


function void pwrmgr_aon_rst_safe_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  wakeup_port    = new("wakeup_port", this);
  reset_req_port = new("reset_req_port", this);
  ast_req_port   = new("ast_req_port", this);
  glitch_port    = new("glitch_port", this);
  clk_valid_port = new("clk_valid_port", this);
  aon_dir_port   = new("aon_dir_port", this);
endfunction : build_phase


task pwrmgr_aon_rst_safe_monitor::collect_trans();
  forever begin
    wakeups_t                 wakeups;
    resets_t                  rstreqs;
    mubi4_t                   sw_rst_req;
    bit                       escalation;
    pwrmgr_pkg::pwr_ast_req_t ast_req;
    logic                     main_pwr_ok;
    logic                     io_clk_val;
    longint unsigned          clk_count;

    @(posedge cfg.vif.clk_slow);

    wakeups     = cfg.vif.wakeups_i;
    rstreqs     = cfg.vif.rstreqs_i;
    sw_rst_req  = cfg.vif.sw_rst_req_i;
    escalation  = cfg.esc_vif.esc_tx_int.esc_p && !cfg.esc_vif.esc_tx_int.esc_n;
    ast_req     = cfg.vif.pwr_ast_req;
    main_pwr_ok = cfg.vif.main_pwr_glitch_n;
    io_clk_val  = cfg.vif.pwr_ast_rsp.io_clk_val;
    clk_count   = cfg.reset_domain.clk_rst_vif.posedge_count;

    // Published ahead of the rest: the registers the device writes only advance while its fast
    // clock runs, so a consumer that gates on this needs it in hand before the events it gates.
    if (!have_previous || io_clk_val !== prev_io_clk_val) begin
      pwrmgr_flag_item item = pwrmgr_flag_item::type_id::create("clk_valid_item");
      item.value     = io_clk_val;
      item.clk_count = clk_count;
      clk_valid_port.write(item);
      aon_dir_port.write(PwrmgrAonClkValid);
    end

    if (!have_previous || wakeups !== prev_wakeups) begin
      pwrmgr_wakeup_item item = pwrmgr_wakeup_item::type_id::create("wakeup_item");
      item.wakeups   = wakeups;
      item.clk_count = clk_count;
      wakeup_port.write(item);
      aon_dir_port.write(PwrmgrAonWakeup);
    end

    if (!have_previous || rstreqs !== prev_rstreqs || sw_rst_req !== prev_sw_rst_req ||
        escalation !== prev_escalation) begin
      pwrmgr_reset_req_item item = pwrmgr_reset_req_item::type_id::create("reset_req_item");
      item.rstreqs    = rstreqs;
      item.sw_rst_req = sw_rst_req;
      item.escalation = escalation;
      item.clk_count  = clk_count;
      reset_req_port.write(item);
      aon_dir_port.write(PwrmgrAonResetReq);
    end

    if (!have_previous || ast_req !== prev_ast_req) begin
      pwrmgr_ast_req_item item = pwrmgr_ast_req_item::type_id::create("ast_req_item");
      item.ast_req   = ast_req;
      item.clk_count = clk_count;
      ast_req_port.write(item);
      aon_dir_port.write(PwrmgrAonAstReq);
    end

    if (!have_previous || main_pwr_ok !== prev_main_pwr_ok) begin
      pwrmgr_flag_item item = pwrmgr_flag_item::type_id::create("glitch_item");
      item.value     = main_pwr_ok;
      item.clk_count = clk_count;
      glitch_port.write(item);
      aon_dir_port.write(PwrmgrAonGlitch);
    end

    prev_wakeups     = wakeups;
    prev_rstreqs     = rstreqs;
    prev_sw_rst_req  = sw_rst_req;
    prev_escalation  = escalation;
    prev_ast_req     = ast_req;
    prev_main_pwr_ok = main_pwr_ok;
    prev_io_clk_val  = io_clk_val;
    have_previous    = 1'b1;
  end
endtask : collect_trans


function void pwrmgr_aon_rst_safe_monitor::reset_monitor();
  have_previous = 1'b0;
endfunction : reset_monitor
