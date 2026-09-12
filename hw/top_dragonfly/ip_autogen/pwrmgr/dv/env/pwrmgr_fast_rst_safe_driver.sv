// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Drives the fast side of the device.
//
// As on the always-on side, two different things live here. Granting the resets the device asks
// for, reporting the clocks it enables, and answering the otp and lifecycle initialization
// requests are what those peers always do, so they run without a test asking. What the
// processor and the non-volatile blocks are doing, and what the rom check reports, is stimulus
// and arrives as an item.
//
// This driver also drives the lifecycle and escalation reset pins. Those follow the grant it has
// just issued, and this driver is not itself reset by them, so it can hold one asserted and
// release it later without the process doing the holding being torn down part way through.
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

  // What this driver last granted, read by the process that drives the leaf reset pins so that
  // it follows the answer given rather than sampling a pin back.
  protected logic granted_lc_src_n;

  // Set once a test has taken control of the rom responses, so the model below stops presenting
  // its own and the test's choice stands.
  protected bit rom_driven_by_item;

  extern virtual task get_and_drive();
  extern virtual function void reset_interface_and_driver();

  extern protected task answer_peer_requests();
  extern protected task model_rom_check();
  extern protected task manage_lc_reset();
  extern protected task drive_items();
  extern protected task drive_item(pwrmgr_fast_item item);
endclass : pwrmgr_fast_rst_safe_driver


task pwrmgr_fast_rst_safe_driver::get_and_drive();
  fork
    answer_peer_requests();
    model_rom_check();
    manage_lc_reset();
    drive_items();
  join
endtask : get_and_drive


function void pwrmgr_fast_rst_safe_driver::reset_interface_and_driver();
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

  // The rom has not finished checking itself yet. A rom that already reported a good result at
  // the instant reset released would be a convenience rather than a model: the real block holds
  // done low until its check completes, and the device waits for it before reaching active.
  // model_rom_check() reports the result afterwards.
  rom_driven_by_item = 1'b0;
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

    // clkmgr reports back the enable it was given.
    cfg.vif.pwr_clk_rsp.main_status <=
        clk_pipe[cfg.cycles_before_clk_status].main_ip_clk_en;
    cfg.vif.pwr_clk_rsp.io_status <=
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


task pwrmgr_fast_rst_safe_driver::manage_lc_reset();
  forever begin
    wait (granted_lc_src_n === 1'b0);
    cfg.lc_clk_rst_vif.drive_rst_pin(1'b0);
    cfg.esc_clk_rst_vif.drive_rst_pin(1'b0);

    wait (granted_lc_src_n === 1'b1);
    // One edge to establish that the clock is running, not a cycle count.
    @(posedge cfg.lc_clk_rst_vif.clk);
    cfg.lc_clk_rst_vif.drive_rst_pin(1'b1);
    cfg.esc_clk_rst_vif.drive_rst_pin(1'b1);
  end
endtask : manage_lc_reset


task pwrmgr_fast_rst_safe_driver::drive_items();
  forever begin
    get_next_item(req);
    drive_item(req);
    item_done();
  end
endtask : drive_items


task pwrmgr_fast_rst_safe_driver::drive_item(pwrmgr_fast_item item);
  pwrmgr_pkg::pwrmgr_cpu_t       cpu;
  rv_core_ibex_pkg::cpu_pwrmgr_t pwr_cpu;

  cpu.ndmreset_req      = item.ndmreset_req;
  pwr_cpu.core_sleeping = item.core_sleeping;

  // Synchronize to the clock first and drive after, so every value on this interface changes on
  // a known edge rather than wherever the item happened to arrive.
  @(posedge cfg.vif.clk);

  cfg.vif.cpu_i   <= cpu;
  cfg.vif.pwr_cpu <= pwr_cpu;

  cfg.vif.pwr_flash.flash_idle <= item.flash_idle;
  cfg.vif.pwr_otp_rsp.otp_idle <= item.otp_idle;
  cfg.vif.pwr_lc_rsp.lc_idle   <= item.lc_idle;

  cfg.vif.lc_hw_debug_en <= item.lc_hw_debug_en;
  cfg.vif.lc_dft_en      <= item.lc_dft_en;

  rom_driven_by_item = 1'b1;
  foreach (item.rom_done[i]) begin
    cfg.vif.rom_ctrl_i[i] <= '{done: item.rom_done[i], good: item.rom_good[i]};
  end
endtask : drive_item
