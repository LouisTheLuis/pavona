// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Drives the fast side of the device.
//
// Granting resets, reporting clocks, and answering the otp and lifecycle initialization requests
// are what those peers always do, so they run without a test asking. What the processor and the
// non-volatile blocks are doing, and what the rom check reports, is stimulus and arrives as an
// item.
//
// It also drives the lc and esc reset pins, which follow the grant it issued and do not reset it.
//
// A template for the same reason as the always-on driver.
class pwrmgr_fast_rst_safe_driver extends dv_rst_safe_base_driver #(
    .ITEM_T(pwrmgr_fast_item),
    .CFG_T (pwrmgr_fast_agent_cfg)
  );

  `uvm_component_utils(pwrmgr_fast_rst_safe_driver)
  `uvm_component_new

  // Deep enough for any delay the configuration can constrain.
  localparam int unsigned MaxFastDelayCycles = 8;

  // The always-on power domain's index into the reset vectors, matching rstmgr_pkg::DomainAonSel.
  // The device's own rst_lc_ni and rst_esc_ni are the leaves of this entry, so this is the bit
  // that decides when they move.
  localparam int unsigned AonDomainSel = 0;

  // The pins this driver holds between items, so an item states only what it changes. Reset puts
  // them back to what the device is released into.
  protected bit held_core_sleeping;
  protected bit held_ndmreset_req;
  protected bit held_flash_idle;
  protected bit held_otp_idle;
  protected bit held_lc_idle;
  protected bit [lc_ctrl_pkg::TxWidth-1:0] held_lc_hw_debug_en;
  protected bit [lc_ctrl_pkg::TxWidth-1:0] held_lc_dft_en;
  protected mubi4_t held_rom_done[pwrmgr_reg_pkg::NumRomInputs];
  protected mubi4_t held_rom_good[pwrmgr_reg_pkg::NumRomInputs];

  // What this driver last granted, read by the process that drives the leaf reset pins so that
  // it follows the answer given rather than sampling a pin back.
  protected logic granted_lc_src_n;

  // Set once a test has taken control of the rom responses, so the model below stops presenting
  // its own and the test's choice stands.
  protected bit rom_driven_by_item;
  // A test asking for the processor to run again just after the device commits to a low power
  // transition. Held here because this driver owns both the input and the answer the device waits
  // on.
  protected bit wake_processor_on_entry_req;
  protected bit hold_clk_status;

  extern virtual task get_and_drive();
  extern virtual function void reset_interface_and_driver();

  extern protected task answer_peer_requests();
  extern protected task model_rom_check();
  extern protected task manage_lc_reset();
  extern protected task manage_invalid_state_forcing();
  // Whether a test has asked for the invalid state, and from where. Served by the process above
  // rather than while an item is being driven.
  protected bit                          force_invalid_requested;
  protected pwrmgr_pkg::fast_pwr_state_e invalid_at_state;
  extern protected task manage_processor_wake_on_entry();
  extern protected task drive_items();
  extern protected task drive_item(pwrmgr_fast_item item);
endclass : pwrmgr_fast_rst_safe_driver


task pwrmgr_fast_rst_safe_driver::get_and_drive();
  cfg.driver_running = 1'b1;
  fork
    answer_peer_requests();
    model_rom_check();
    manage_lc_reset();
    manage_processor_wake_on_entry();
    manage_invalid_state_forcing();
    drive_items();
  join
endtask : get_and_drive


function void pwrmgr_fast_rst_safe_driver::reset_interface_and_driver();
  cfg.driver_running = 1'b0;
  // At power on rstmgr is holding both resets, no clock has been reported, and neither otp nor
  // lifecycle has finished initializing.
  cfg.vif.pwr_rst_rsp <= '0;
  cfg.vif.pwr_clk_rsp <= '0;
  cfg.vif.pwr_lc_rsp  <= '0;
  cfg.vif.pwr_otp_rsp <= '0;

  granted_lc_src_n = 1'b0;

  // The processor is awake and the non-volatile blocks are idle, which is what those peers look
  // like when nothing is happening. A test that wants the processor asleep, or a low power
  // transition aborted, says so with an item.
  cfg.vif.cpu_i   <= pwrmgr_pkg::PWRMGR_CPU_DEFAULT;
  cfg.vif.pwr_cpu <= rv_core_ibex_pkg::CPU_PWRMGR_DEFAULT;
  cfg.vif.pwr_flash.flash_idle <= 1'b1;

  cfg.vif.lc_hw_debug_en <= lc_ctrl_pkg::Off;
  cfg.vif.lc_dft_en      <= lc_ctrl_pkg::Off;

  held_core_sleeping  = 1'b0;
  held_ndmreset_req   = 1'b0;
  held_flash_idle     = 1'b1;
  held_otp_idle       = 1'b1;
  held_lc_idle        = 1'b1;
  held_lc_hw_debug_en = lc_ctrl_pkg::Off;
  held_lc_dft_en      = lc_ctrl_pkg::Off;
  for (int unsigned i = 0; i < pwrmgr_reg_pkg::NumRomInputs; i++) begin
    held_rom_done[i] = MuBi4True;
    held_rom_good[i] = MuBi4True;
  end

  // The alert handler is reset too, so it stops escalating. Driving the idle encoding rather
  // than clearing to zero, because the pair is differential and an undriven receiver input
  // leaves the device's escalation output unknown.

  // The rom has not finished checking itself yet: the real block holds done low until its check
  // completes, and the device waits for it before reaching active. Any invalid-state override goes
  // with the reset, because the signal it overrides is a flop on this reset. Unconditional, since
  // the item thread that asked may have been killed part way through.
  cfg.vif.release_invalid_state();

  rom_driven_by_item          = 1'b0;
  wake_processor_on_entry_req = 1'b0;
  force_invalid_requested     = 1'b0;
  hold_clk_status             = 1'b0;
  for (int unsigned i = 0; i < pwrmgr_reg_pkg::NumRomInputs; i++) begin
    cfg.vif.rom_ctrl_i[i] <= rom_ctrl_pkg::PWRMGR_DATA_DEFAULT;
  end
endfunction : reset_interface_and_driver


// Each answer is delayed by a fixed number of fast clocks, taken out of a pipeline the request
// is shifted into. The delay is fixed for the whole test, which is what keeps several requests
// in flight at once in the order they arrived.
task pwrmgr_fast_rst_safe_driver::answer_peer_requests();
  logic [pwrmgr_pkg::PowerDomains-1:0] rst_lc_pipe [MaxFastDelayCycles+1];
  logic [pwrmgr_pkg::PowerDomains-1:0] rst_sys_pipe[MaxFastDelayCycles+1];
  pwrmgr_pkg::pwr_clk_req_t            clk_pipe    [MaxFastDelayCycles+1];
  logic                                lc_init_pipe[MaxFastDelayCycles+1];
  logic                                otp_init_pipe[MaxFastDelayCycles+1];

  foreach (rst_lc_pipe[i]) begin
    rst_lc_pipe[i]   = '0;
    rst_sys_pipe[i]  = '0;
    clk_pipe[i]      = '0;
    lc_init_pipe[i]  = '0;
    otp_init_pipe[i] = '0;
  end

  forever begin
    @(posedge cfg.vif.clk);

    for (int i = MaxFastDelayCycles; i > 0; i--) begin
      rst_lc_pipe[i]   = rst_lc_pipe[i-1];
      rst_sys_pipe[i]  = rst_sys_pipe[i-1];
      clk_pipe[i]      = clk_pipe[i-1];
      lc_init_pipe[i]  = lc_init_pipe[i-1];
      otp_init_pipe[i] = otp_init_pipe[i-1];
    end
    rst_lc_pipe[0]   = cfg.vif.pwr_rst_req.rst_lc_req;
    rst_sys_pipe[0]  = cfg.vif.pwr_rst_req.rst_sys_req;
    clk_pipe[0]      = cfg.vif.pwr_clk_req;
    lc_init_pipe[0]  = cfg.vif.pwr_lc_req.lc_init;
    otp_init_pipe[0] = cfg.vif.pwr_otp_req.otp_init;

    // A request for a reset is granted by taking the matching source low.
    cfg.vif.pwr_rst_rsp.rst_lc_src_n <=
        ~rst_lc_pipe[cfg.cycles_before_rst_lc_src];
    cfg.vif.pwr_rst_rsp.rst_sys_src_n <=
        ~rst_sys_pipe[cfg.cycles_before_rst_sys_src];

    // clkmgr reports back the enable it was given, unless a wake is being placed against the start
    // of a low power transition. Holding this answer holds the device, which is what lets the wake
    // be placed.
    if (!hold_clk_status) cfg.vif.pwr_clk_rsp.main_status <=
        clk_pipe[cfg.cycles_before_clk_status].main_ip_clk_en;
    if (!hold_clk_status) cfg.vif.pwr_clk_rsp.io_status <=
        clk_pipe[cfg.cycles_before_clk_status].io_ip_clk_en;

    cfg.vif.pwr_lc_rsp.lc_done   <= lc_init_pipe[cfg.cycles_before_lc_done];
    cfg.vif.pwr_otp_rsp.otp_done <= otp_init_pipe[cfg.cycles_before_otp_done];

    granted_lc_src_n = ~rst_lc_pipe[cfg.cycles_before_rst_lc_src][AonDomainSel];
  end
endtask : answer_peer_requests


// The rom checks itself once after each reset and then reports the outcome. The time it takes
// is the device's boot time as this testbench presents it, which is why the bound sits with the
// other peer latencies in the agent configuration rather than in a test.
task pwrmgr_fast_rst_safe_driver::model_rom_check();
  repeat (cfg.cycles_before_rom_done) @(posedge cfg.vif.clk);

  // A test that has already spoken for the rom keeps its answer.
  if (rom_driven_by_item) return;

  for (int unsigned i = 0; i < pwrmgr_reg_pkg::NumRomInputs; i++) begin
    cfg.vif.rom_ctrl_i[i] <= '{done: MuBi4True, good: MuBi4True};
  end
endtask : model_rom_check


// Wakes the processor just after the device commits to a low power transition.
//
// The request is honored from the device being active: one placed while it is still coming up
// waits, rather than withdrawing the processor from a transition that never began. The wake lands
// when the device leaves that state, which is the transition starting.
//
// There is no window to hit. The clock manager's answer is held from the moment the device is
// active until the wake has landed, and the device cannot reach the state where it asks whether
// the processor is still asleep until that answer arrives.
task pwrmgr_fast_rst_safe_driver::manage_processor_wake_on_entry();
  forever begin
    wait (wake_processor_on_entry_req);

    // The state, not the fetch enable: the item drives the processor asleep as it lands, so the
    // device can assign the enable off in the same cycle it would have assigned it on, and a wait
    // on that enable rising never returns.
    wait (cfg.vif.fast_state == pwrmgr_pkg::FastPwrStateActive);
    hold_clk_status = 1'b1;

    wait (cfg.vif.fast_state != pwrmgr_pkg::FastPwrStateActive);
    // The held value moves with the pin, or the next item, which says nothing about the processor,
    // would put it back to sleep.
    held_core_sleeping = 1'b0;
    cfg.vif.pwr_cpu.core_sleeping <= 1'b0;
    @(posedge cfg.vif.clk);

    hold_clk_status             = 1'b0;
    wake_processor_on_entry_req = 1'b0;
  end
endtask : manage_processor_wake_on_entry


// Evaluated every cycle, like the thing it watches. If a test named a state and the machine is in
// it, send it now; nothing waits and nothing is held.
// Waits on the state value rather than on a clock edge. The state register is written by a
// non-blocking assignment, which lands after the active items at that edge, so a process woken by
// the edge would still read the state the machine held before it. Several states here last a
// single cycle, so that read would name a state the machine has already left.
task pwrmgr_fast_rst_safe_driver::manage_invalid_state_forcing();
  forever begin
    wait (force_invalid_requested && cfg.vif.fast_state == invalid_at_state);
    force_invalid_requested = 1'b0;
    `uvm_info(`gfn, $sformatf("Sending the state machine to invalid from %0s",
                              invalid_at_state.name()), UVM_MEDIUM)
    cfg.vif.force_invalid_state();
  end
endtask : manage_invalid_state_forcing


// Grants the lifecycle reset only. The escalation reset moves with the escalation clock, which the
// always-on driver owns, because the device reads a released reset with a stopped clock as the
// escalation path having failed.
task pwrmgr_fast_rst_safe_driver::manage_lc_reset();
  forever begin
    wait (granted_lc_src_n === 1'b0);
    cfg.lc_clk_rst_vif.drive_rst_pin(1'b0);

    wait (granted_lc_src_n === 1'b1);
    // One edge to establish that the clock is running, not a cycle count.
    @(posedge cfg.lc_clk_rst_vif.clk);
    cfg.lc_clk_rst_vif.drive_rst_pin(1'b1);
  end
endtask : manage_lc_reset


task pwrmgr_fast_rst_safe_driver::drive_items();
  forever begin
    get_next_item(req);
    drive_item(req);
    item_done();
  end
endtask : drive_items


// Nothing is waited for at the end. Every item restates the whole of its side, so an item
// overwritten before it lands loses nothing. Waiting would hold the item open across a low power
// window, where this driver's clock is taken away.
task pwrmgr_fast_rst_safe_driver::drive_item(pwrmgr_fast_item item);
  pwrmgr_pkg::pwrmgr_cpu_t       cpu;
  rv_core_ibex_pkg::cpu_pwrmgr_t pwr_cpu;

  repeat (item.apply_delay_cycles) @(posedge cfg.vif.clk);

  if (item.change_core_sleeping) held_core_sleeping = item.core_sleeping;
  if (item.change_ndmreset_req)  held_ndmreset_req  = item.ndmreset_req;
  if (item.change_idles) begin
    held_flash_idle = item.flash_idle;
    held_otp_idle   = item.otp_idle;
    held_lc_idle    = item.lc_idle;
  end
  if (item.change_lc) begin
    held_lc_hw_debug_en = item.lc_hw_debug_en;
    held_lc_dft_en      = item.lc_dft_en;
  end
  // A test answering for the rom takes the answer over for good. model_rom_check() stands down
  // once this is set, so the driver's own reply cannot arrive later and overwrite what was asked
  // for; the reset puts both back.
  if (item.change_rom) begin
    rom_driven_by_item = 1'b1;
    for (int unsigned i = 0; i < pwrmgr_reg_pkg::NumRomInputs; i++) begin
      held_rom_done[i] = item.rom_done[i];
      held_rom_good[i] = item.rom_good[i];
    end
  end

  cpu.ndmreset_req      = held_ndmreset_req;
  pwr_cpu.core_sleeping = held_core_sleeping;

  cfg.vif.cpu_i   <= cpu;
  cfg.vif.pwr_cpu <= pwr_cpu;

  cfg.vif.pwr_flash.flash_idle <= held_flash_idle;
  cfg.vif.pwr_otp_rsp.otp_idle <= held_otp_idle;
  cfg.vif.pwr_lc_rsp.lc_idle   <= held_lc_idle;

  if (rom_driven_by_item) begin
    for (int unsigned i = 0; i < pwrmgr_reg_pkg::NumRomInputs; i++) begin
      cfg.vif.rom_ctrl_i[i] <= '{done: held_rom_done[i], good: held_rom_good[i]};
    end
  end

  cfg.vif.lc_hw_debug_en <= lc_ctrl_pkg::lc_tx_t'(held_lc_hw_debug_en);
  cfg.vif.lc_dft_en      <= lc_ctrl_pkg::lc_tx_t'(held_lc_dft_en);

  // Corrupting the state machine. The sequence named the state; waiting for it belongs here. The
  // corruption goes through the fault interface bound to every sparse state machine. Asked for, not
  // served here: manage_processor_wake_on_entry() places it, because a driver serving an item must
  // not block.
  if (item.wake_processor_on_entry) wake_processor_on_entry_req = 1'b1;

  if (item.force_fsm_invalid) begin
    invalid_at_state = item.invalid_at_state;
    force_invalid_requested = 1'b1;
  end

endtask : drive_item
