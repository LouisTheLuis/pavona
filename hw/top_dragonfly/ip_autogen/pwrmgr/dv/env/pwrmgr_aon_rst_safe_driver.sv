// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Drives the always-on side of the device.
//
// AST's answers to the power and clock requests run on their own; wakeup and reset requests are
// stimulus and arrive as items. Both live under get_and_drive(), because the base class kills that
// thread at reset and takes its sub processes with it.
//
// It also restores the fast, lc and esc clocks and releases the fast domain's reset, which follow
// from the answer just given.
//
// A template because the clock handshake is written once per clock the top has.
class pwrmgr_aon_rst_safe_driver extends dv_rst_safe_base_driver #(
    .ITEM_T(pwrmgr_aon_item),
    .CFG_T (pwrmgr_aon_agent_cfg)
  );

  `uvm_component_utils(pwrmgr_aon_rst_safe_driver)
  `uvm_component_new

  // Deep enough for any delay the configuration can constrain.
  localparam int unsigned MaxAstDelayCycles = 16;

  // What this driver last told the device about the io clock. Kept locally so the process that
  // manages the fast domain reads the answer this driver gave rather than sampling a pin.
  protected logic io_clk_valid;

  extern virtual task get_and_drive();
  extern virtual function void reset_interface_and_driver();

  extern protected task answer_ast_requests();
  extern protected task clear_peripheral_requests_on_lc_reset();
  extern protected task manage_fast_domain();
  extern protected task set_alert_clocks(bit running);

  extern protected task manage_esc_domain();
  // What a test has asked of the escalation side. Read by the two managers above, the only things
  // that touch those pins. The always-on domain's index into the reset vectors, matching
  // rstmgr_pkg::DomainAonSel.
  localparam int unsigned AonDomainSel = 0;

  // The three levels the device sees on this side. Held here and nowhere else, so the withdrawal
  // below and a later item cannot disagree about what is being driven.
  protected wakeups_t         held_wakeups;
  protected resets_t          held_rstreqs;
  protected bit [MUBI4W-1:0]  held_sw_rst_req = MuBi4False;
  // Escalation is held the same way. Without this, an item about something else would carry the
  // item's default and drop the escalation pins, so every sequence would have to restate values
  // it has no interest in.
  protected bit               held_escalation_reset;
  protected bit               held_esc_clk_stopped;
  protected bit               held_esc_rst_asserted;
  protected bit               esc_clk_malfunction_req;
  protected bit               esc_rst_malfunction_req;

  extern protected task drive_items();
  extern protected task drive_item(pwrmgr_aon_item item);
endclass : pwrmgr_aon_rst_safe_driver


task pwrmgr_aon_rst_safe_driver::get_and_drive();
  fork
    answer_ast_requests();
    clear_peripheral_requests_on_lc_reset();
    manage_fast_domain();
    manage_esc_domain();
    drive_items();
  join
endtask : get_and_drive


function void pwrmgr_aon_rst_safe_driver::reset_interface_and_driver();
  // AST has nothing to report until the device asks again. These are the values it presents at
  // power on.
  cfg.vif.pwr_ast_rsp  <= '0;
  held_wakeups    = '0;
  held_rstreqs    = '0;
  held_sw_rst_req = MuBi4False;
  held_escalation_reset = 1'b0;
  held_esc_clk_stopped  = 1'b0;
  held_esc_rst_asserted = 1'b0;
  cfg.vif.wakeups_i    <= held_wakeups;
  cfg.vif.rstreqs_i    <= held_rstreqs;
  cfg.vif.sw_rst_req_i <= mubi4_t'(held_sw_rst_req);
  cfg.vif.main_pwr_glitch_n <= 1'b1;

  io_clk_valid = 1'b0;

  // Nothing has been asked of the escalation side, and the signalling sits in the encoding that
  // says nothing is being escalated. This agent owns those, so it is what puts them back.
  esc_clk_malfunction_req = 1'b0;
  esc_rst_malfunction_req = 1'b0;
  cfg.esc_vif.esc_tx_int.esc_p = 1'b0;
  cfg.esc_vif.esc_tx_int.esc_n = 1'b1;

  // The device's clock requests reset to zero, so AST stops providing the clocks. The alert
  // clocks go with them: the side that pings is as unclocked as the sender it pings while the
  // source is away, here for the same reason as when the device asks for low power.
  cfg.fast_clk_rst_vif.stop_clk();
  cfg.lc_clk_rst_vif.stop_clk();
  cfg.esc_clk_rst_vif.stop_clk();
  foreach (cfg.alert_clk_rst_vifs[i]) cfg.alert_clk_rst_vifs[i].stop_clk();

  // The device's other three resets are leaves of the power-on reset, built from synchronizers this
  // reset clears directly, so they fall in the same instant with no clock involved.
  //
  // They are released elsewhere: a leaf comes back only once its clock is running. Assigned rather
  // than driven through drive_rst_pin(), which is a task where this is a function.
  cfg.fast_clk_rst_vif.o_rst_n = 1'b0;
  cfg.lc_clk_rst_vif.o_rst_n   = 1'b0;
  cfg.esc_clk_rst_vif.o_rst_n  = 1'b0;
endfunction : reset_interface_and_driver


// The answer to each request is delayed by a fixed number of slow clocks, implemented as a
// shift register the answer is read out of. The delay is fixed for the whole test, which is
// what keeps several requests in flight at once in the order they arrived.
task pwrmgr_aon_rst_safe_driver::answer_ast_requests();
  logic [MaxAstDelayCycles:0] main_clk_sr;
  logic [MaxAstDelayCycles:0] io_clk_sr;
  logic [MaxAstDelayCycles:0] main_pok_sr;

  main_clk_sr = '0;
  io_clk_sr = '0;
  main_pok_sr = '0;

  forever begin
    @(posedge cfg.vif.clk_slow);

    main_clk_sr = {main_clk_sr[MaxAstDelayCycles-1:0],
                     cfg.vif.pwr_ast_req.core_clk_en};
    io_clk_sr = {io_clk_sr[MaxAstDelayCycles-1:0],
                     cfg.vif.pwr_ast_req.io_clk_en};
    main_pok_sr = {main_pok_sr[MaxAstDelayCycles-1:0],
                   cfg.vif.pwr_ast_req.main_pd_n};

    cfg.vif.pwr_ast_rsp.core_clk_val <=
        main_clk_sr[cfg.cycles_before_clk_val];
    cfg.vif.pwr_ast_rsp.io_clk_val <=
        io_clk_sr[cfg.cycles_before_clk_val];
    cfg.vif.pwr_ast_rsp.main_pok <= main_pok_sr[cfg.cycles_before_main_pok];

    // The slow clock is the one clock the device never asks AST to stop.
    cfg.vif.pwr_ast_rsp.slow_clk_val <= 1'b1;

    io_clk_valid = io_clk_sr[cfg.cycles_before_clk_val];
  end
endtask : answer_ast_requests


// The peripherals raising reset requests sit in the lc reset domain, so granting an lc reset stops
// them asking. Without it the device would find the request still asserted and reset again,
// endlessly.
task pwrmgr_aon_rst_safe_driver::clear_peripheral_requests_on_lc_reset();
  forever begin
    @(negedge cfg.lc_clk_rst_vif.rst_n);

    // The peripherals that raise these sit in the lifecycle reset domain, so granting that reset
    // resets them and they stop asking. The held values move with the pins: if only the pins were
    // cleared, the next item would put back whatever was being driven before.
    held_rstreqs    = '0;
    held_sw_rst_req = MuBi4False;
    cfg.vif.rstreqs_i    <= held_rstreqs;
    cfg.vif.sw_rst_req_i <= mubi4_t'(held_sw_rst_req);
  end
endtask : clear_peripheral_requests_on_lc_reset


// The alert clocks are taken away and given back with the rest. Only the generators the
// environment granted this agent are touched; the alert agents themselves are left alone.
task pwrmgr_aon_rst_safe_driver::set_alert_clocks(bit running);
  foreach (cfg.alert_clk_rst_vifs[i]) begin
    if (running) begin
      // Restarted without advancing time, because this sits alongside the other clocks rather
      // than waiting on any of them.
      cfg.alert_clk_rst_vifs[i].start_clk(.wait_for_posedge(1'b0));
    end else begin
      cfg.alert_clk_rst_vifs[i].stop_clk();
    end
  end
endtask : set_alert_clocks

// The one place that starts and stops the escalation clock, so the device powering down and a test
// breaking the path cannot take it from each other.
//
// The device decides its escalation path has failed if that clock stops while it expects it, and
// the counter deciding this is held by the escalation reset. Any interval where the reset is
// released and the clock is not ticking is a failure it can see, so the clock starts before the
// reset is released and the reset is asserted before the clock stops. A test breaking the path on
// purpose is the exception.
task pwrmgr_aon_rst_safe_driver::manage_esc_domain();
  forever begin
    // Down: the reset goes on first, then the clock goes away.
    //
    // The alert handler driving the escalation pair shares this reset on a real device, so keeping
    // the pair asserted across the domain going down would hand the receiver an escalation it
    // cannot acknowledge in time and it would report a protocol error. The malfunction requests are
    // left alone, since they are what holds this reset.
    held_escalation_reset = 1'b0;
    cfg.esc_vif.esc_tx_int.esc_p <= 1'b0;
    cfg.esc_vif.esc_tx_int.esc_n <= 1'b1;

    cfg.esc_clk_rst_vif.drive_rst_pin(1'b0);
    cfg.esc_clk_rst_vif.stop_clk();

    wait (io_clk_valid === 1'b1 &&
          cfg.vif.pwr_rst_rsp.rst_lc_src_n[AonDomainSel] === 1'b1);

    // Up: the clock runs first, and only once it is ticking does the reset come off.
    cfg.esc_clk_rst_vif.start_clk();
    @(posedge cfg.esc_clk_rst_vif.clk);
    cfg.esc_clk_rst_vif.drive_rst_pin(1'b1);

    // Held here while the domain is up. A test breaking the path takes the clock away without
    // the reset; the device is meant to notice that and reset itself, which brings us back
    // round through the domain going down.
    fork
      begin : wait_domain_down
        wait (io_clk_valid === 1'b0 ||
              cfg.vif.pwr_rst_rsp.rst_lc_src_n[AonDomainSel] === 1'b0);
      end
      begin : serve_malfunction
        forever begin
          wait (esc_clk_malfunction_req || esc_rst_malfunction_req);
          if (esc_clk_malfunction_req) cfg.esc_clk_rst_vif.stop_clk();
          if (esc_rst_malfunction_req) cfg.esc_clk_rst_vif.drive_rst_pin(1'b0);

          wait (!esc_clk_malfunction_req && !esc_rst_malfunction_req);
          cfg.esc_clk_rst_vif.start_clk();
          @(posedge cfg.esc_clk_rst_vif.clk);
          cfg.esc_clk_rst_vif.drive_rst_pin(1'b1);
        end
      end
    join_any
    disable fork;
  end
endtask : manage_esc_domain


task pwrmgr_aon_rst_safe_driver::manage_fast_domain();
  forever begin
    wait (io_clk_valid === 1'b1);
    cfg.fast_clk_rst_vif.start_clk();
    cfg.lc_clk_rst_vif.start_clk();
    cfg.esc_clk_rst_vif.start_clk();
    set_alert_clocks(1'b1);


    // The requirement is that the clock is running before the leaf can be released, not that a
    // particular number of cycles has passed. One edge establishes that; counting cycles beyond
    // it would be a delay standing in for a condition.
    @(posedge cfg.fast_clk_rst_vif.clk);
    // A leaf cannot come out of reset while its parent is still in it, whatever the clock is
    // doing. Without this the release can land in the window between the power-on reset
    // asserting and this driver being torn down by it.
    if (cfg.reset_domain.clk_rst_vif.rst_n === 1'b1) begin
      cfg.fast_clk_rst_vif.drive_rst_pin(1'b1);
    end

    wait (io_clk_valid === 1'b0);
    // Losing the clock is not a reset. The fast domain keeps its state until the device asks
    // for the clock again, which is what makes a wakeup resume rather than restart.
    cfg.fast_clk_rst_vif.stop_clk();
    cfg.lc_clk_rst_vif.stop_clk();
    cfg.esc_clk_rst_vif.stop_clk();
    set_alert_clocks(1'b0);

  end
endtask : manage_fast_domain


task pwrmgr_aon_rst_safe_driver::drive_items();
  forever begin
    get_next_item(req);
    drive_item(req);
    item_done();
  end
endtask : drive_items


task pwrmgr_aon_rst_safe_driver::drive_item(pwrmgr_aon_item item);
  repeat (item.apply_delay_cycles) @(posedge cfg.vif.clk_slow);

  if (item.change_wakeups)    held_wakeups    = item.wakeups;
  if (item.change_rstreqs)    held_rstreqs    = item.rstreqs;
  if (item.change_sw_rst_req) held_sw_rst_req = item.sw_rst_req;
  if (item.change_escalation) begin
    held_escalation_reset = item.escalation_reset;
    held_esc_clk_stopped  = item.esc_clk_stopped;
    held_esc_rst_asserted = item.esc_rst_asserted;
  end

  cfg.vif.wakeups_i    <= held_wakeups;
  cfg.vif.rstreqs_i    <= held_rstreqs;
  cfg.vif.sw_rst_req_i <= mubi4_t'(held_sw_rst_req);
  @(posedge cfg.vif.clk_slow);

  cfg.esc_vif.esc_tx_int.esc_p <= held_escalation_reset;
  cfg.esc_vif.esc_tx_int.esc_n <= ~held_escalation_reset;

  esc_rst_malfunction_req = held_esc_rst_asserted;
  if (held_esc_clk_stopped && item.esc_clk_stopped_cycles > 0) begin
    // A measured interruption. Counted on the clock the device counts, which is running
    // because this only makes sense while the device is up.
    esc_clk_malfunction_req = 1'b1;
    repeat (item.esc_clk_stopped_cycles) @(posedge cfg.fast_clk_rst_vif.clk);
    esc_clk_malfunction_req = 1'b0;
    // The interruption is not over when the clock comes back: the device's count is cleared by an
    // acknowledgment that crosses into the escalation domain and back, so the clock has to run for
    // that round trip. Handing control back sooner merges two interruptions into one.
    repeat (EscTimeoutAckCycles) @(posedge cfg.esc_clk_rst_vif.clk);
    // A measured interruption is one action rather than a state to stay in. The clock is back, so
    // the held value goes with it; leaving it set would have the next item, which says nothing
    // about escalation, stop the clock again and never start it.
    held_esc_clk_stopped = 1'b0;
  end else begin
    esc_clk_malfunction_req = held_esc_clk_stopped;
  end

  if (item.power_glitch) begin
    cfg.vif.disable_power_glitch_assertion();
    cfg.vif.main_pwr_glitch_n <= 1'b0;
    repeat (item.glitch_width_slow_clks) @(posedge cfg.vif.clk_slow);
    cfg.vif.main_pwr_glitch_n <= 1'b1;
  end
endtask : drive_item
