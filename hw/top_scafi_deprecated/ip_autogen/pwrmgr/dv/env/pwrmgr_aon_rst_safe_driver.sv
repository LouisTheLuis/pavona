// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Drives the always-on side of the device.
//
// Two things happen here and they are not the same kind of thing. Answering the device's power
// and clock requests is what AST always does, so it runs on its own and no test asks for it.
// Telling the device that a peripheral wants a wakeup or a reset is stimulus, so it arrives as
// an item. Both live under get_and_drive() because the base class kills that one thread at
// reset, and killing it takes the sub processes with it.
//
// This driver also restores the fast, lc and esc clocks, and releases the fast domain's reset.
// Those belong here because they are consequences of the answer it just gave: the clocks exist
// only while AST says the clock is valid, and rstmgr cannot release a leaf reset until that
// clock is running again.
//
// A template because the clock handshake below is written once per clock the top has, and which
// clocks exist is decided when the top is built. The monitor and the agent have no per clock code,
// so they are plain source.
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
  extern protected task drive_items();
  extern protected task drive_item(pwrmgr_aon_item item);
endclass : pwrmgr_aon_rst_safe_driver


task pwrmgr_aon_rst_safe_driver::get_and_drive();
  fork
    answer_ast_requests();
    clear_peripheral_requests_on_lc_reset();
    manage_fast_domain();
    drive_items();
  join
endtask : get_and_drive


function void pwrmgr_aon_rst_safe_driver::reset_interface_and_driver();
  // AST has nothing to report until the device asks again. These are the values it presents at
  // power on.
  cfg.vif.pwr_ast_rsp  <= '0;
  cfg.vif.wakeups_i    <= '0;
  cfg.vif.rstreqs_i    <= '0;
  cfg.vif.sw_rst_req_i <= MuBi4False;
  cfg.vif.main_pwr_glitch_n <= 1'b1;

  io_clk_valid = 1'b0;

  // The device's clock requests reset to zero, so AST stops providing the clocks.
  cfg.fast_clk_rst_vif.stop_clk();
  cfg.lc_clk_rst_vif.stop_clk();
  cfg.esc_clk_rst_vif.stop_clk();

  // The device's other three resets are leaves of the power-on reset: rstmgr builds each from a
  // synchronizer that this reset clears directly, so they fall in the same instant with no clock
  // involved. This function runs at that instant, which is why they are asserted here.
  //
  // They are released elsewhere and deliberately not here: a leaf comes back only once its clock
  // is running, which the device has to ask for. The fast domain's reset is released by
  // manage_fast_domain() below, and the lc and esc resets by the fast driver, which grants them.
  //
  // Assigned rather than driven through drive_rst_pin(), because that is a task and this is a
  // function. The assignment is what the task does.
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
  logic [MaxAstDelayCycles:0] usb_clk_sr;
  logic [MaxAstDelayCycles:0] main_pok_sr;

  main_clk_sr = '0;
  io_clk_sr = '0;
  usb_clk_sr = '0;
  main_pok_sr = '0;

  forever begin
    @(posedge cfg.vif.clk_slow);

    main_clk_sr = {main_clk_sr[MaxAstDelayCycles-1:0],
                     cfg.vif.pwr_ast_req.core_clk_en};
    io_clk_sr = {io_clk_sr[MaxAstDelayCycles-1:0],
                     cfg.vif.pwr_ast_req.io_clk_en};
    usb_clk_sr = {usb_clk_sr[MaxAstDelayCycles-1:0],
                     cfg.vif.pwr_ast_req.usb_clk_en};
    main_pok_sr = {main_pok_sr[MaxAstDelayCycles-1:0],
                   cfg.vif.pwr_ast_req.main_pd_n};

    cfg.vif.pwr_ast_rsp.core_clk_val <=
        main_clk_sr[cfg.cycles_before_clk_val];
    cfg.vif.pwr_ast_rsp.io_clk_val <=
        io_clk_sr[cfg.cycles_before_clk_val];
    cfg.vif.pwr_ast_rsp.usb_clk_val <=
        usb_clk_sr[cfg.cycles_before_clk_val];
    cfg.vif.pwr_ast_rsp.main_pok <= main_pok_sr[cfg.cycles_before_main_pok];

    // The slow clock is the one clock the device never asks AST to stop.
    cfg.vif.pwr_ast_rsp.slow_clk_val <= 1'b1;

    io_clk_valid = io_clk_sr[cfg.cycles_before_clk_val];
  end
endtask : answer_ast_requests


// The peripherals that raise reset requests sit in the lc reset domain, so granting an lc reset
// resets them too and they stop asking. Without this the device would find the request still
// asserted when it came back and reset again immediately, without end. The lc reset pin is
// driven by the fast agent, which is the component that grants it.
task pwrmgr_aon_rst_safe_driver::clear_peripheral_requests_on_lc_reset();
  forever begin
    @(negedge cfg.lc_clk_rst_vif.rst_n);
    cfg.vif.rstreqs_i    <= '0;
    cfg.vif.sw_rst_req_i <= MuBi4False;
  end
endtask : clear_peripheral_requests_on_lc_reset


task pwrmgr_aon_rst_safe_driver::manage_fast_domain();
  forever begin
    wait (io_clk_valid === 1'b1);
    cfg.fast_clk_rst_vif.start_clk();
    cfg.lc_clk_rst_vif.start_clk();
    cfg.esc_clk_rst_vif.start_clk();

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
  cfg.vif.wakeups_i    <= item.wakeups;
  cfg.vif.rstreqs_i    <= item.rstreqs;
  cfg.vif.sw_rst_req_i <= item.sw_rst_req;
  @(posedge cfg.vif.clk_slow);

  if (item.power_glitch) begin
    cfg.vif.main_pwr_glitch_n <= 1'b0;
    repeat (item.glitch_width_slow_clks) @(posedge cfg.vif.clk_slow);
    cfg.vif.main_pwr_glitch_n <= 1'b1;
  end
endtask : drive_item
