// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package pwrmgr_env_pkg;
  // dep packages
  import uvm_pkg::*;
  import top_pkg::*;
  import dv_utils_pkg::*;
  import dv_lib_pkg::*;
  import tl_agent_pkg::*;
  // reset_seq and delay_seq, started by the reset-safe sequences on the inherited sequencers.
  import clk_rst_agent_pkg::*;
  import cip_base_pkg::*;
  import dv_base_reg_pkg::*;
  import csr_utils_pkg::*;
  import pwrmgr_ral_pkg::*;
  import alert_esc_agent_pkg::*;
  import pwrmgr_pkg::PowerDomains;
  import rv_core_ibex_pkg::CPU_PWRMGR_DEFAULT;
  import prim_mubi_pkg::mubi4_t;
  import prim_mubi_pkg::MuBi4False;
  import prim_mubi_pkg::MuBi4True;
  import prim_mubi_pkg::MuBi4Width;
  import sec_cm_pkg::*;
  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // parameters
  parameter int NUM_INTERRUPTS = 1;

  // clk enable disable delay
  // How many bus clock cycles this top fits inside one always-on cycle. Taken from the clock
  // frequencies the top is built with rather than from a measurement, because the two tops differ
  // by a large factor: one runs pwrmgr's bus clock at a hundred and twenty times its always-on
  // clock and the other at four times. Anything the testbench counts in always-on cycles covers
  // that many times more bus clock work on the first, so a number that lands where it should on
  // one top lands somewhere else entirely on the other.
  // The ratio is rounded up, so a top whose two frequencies do not divide exactly is modeled with
  // an always-on cycle at least as long as the real one rather than a shorter one. Both tops
  // built today divide exactly, so the rounding does not move either of them.
  parameter uint BusCyclesPerAonCycle = 120;

  // How long one low power operation takes, in always-on cycles. Measured on both tops as about
  // twenty three always-on cycles of handshaking between the two domains plus about fifty bus
  // clock cycles of work, and the bus part costs fewer always-on cycles the wider the ratio is.
  // A reset meant to land inside the operation has to be placed against this rather than against
  // a count taken on one top: the same number of always-on cycles overshoots on a top that fits
  // more bus clock work into each of them.
  // The bus part is rounded up to a whole always-on cycle: fifty bus cycles is less than one
  // always-on cycle on a top with a wide ratio, and truncating it to zero would claim the
  // operation is shorter than it is.
  parameter uint LowPowerOpAonCycles = 23 + (50 + BusCyclesPerAonCycle - 1) / BusCyclesPerAonCycle;

  parameter uint MAIN_CLK_DELAY_MIN = 15;
  parameter uint MAIN_CLK_DELAY_MAX = 258;
  parameter uint ESC_CLK_DELAY_MIN = 1;
  parameter uint ESC_CLK_DELAY_MAX = 10;

  // alerts
  parameter uint NUM_ALERTS = 1;
  parameter string LIST_OF_ALERTS[NUM_ALERTS] = {"fatal_fault"};

  // types
  typedef enum int {
    WakeupSysrst,
    WakeupDbgCable,
    WakeupPin,
    WakeupUsb,
    WakeupAonTimer,
    WakeupSensorCtrl
  } wakeup_e;

  typedef enum int {
    PwrmgrMubiNone = 0,
    PwrmgrMubiLcCtrl = 1,
    PwrmgrMubiRomCtrl = 2
  } pwrmgr_mubi_e;

  typedef struct packed {
    logic main_pd_n;
    logic usb_clk_en_active;
    logic usb_clk_en_lp;
    logic io_clk_en;
    logic main_clk_en;
  } control_enables_t;

  // Names the port a monitor has just written, published alongside the item so that events
  // arriving on different ports can be put back in order by a consumer.
  typedef enum int {
    PwrmgrAonWakeup,
    PwrmgrAonResetReq,
    PwrmgrAonAstReq,
    PwrmgrAonGlitch
  } pwrmgr_aon_obs_kind_e;

  typedef enum int {
    PwrmgrFastActive,
    PwrmgrFastLowPower,
    PwrmgrFastStrap,
    PwrmgrFastIntr,
    PwrmgrFastPeerReq
  } pwrmgr_fast_obs_kind_e;

  typedef bit [pwrmgr_reg_pkg::NumWkups-1:0] wakeups_t;
  typedef bit [pwrmgr_reg_pkg::NumRstReqs-1:0] resets_t;

  // This is used to send all resets to rstmgr.
  typedef bit [pwrmgr_pkg::HwResetWidth-1:0] resets_out_t;

  // need a short name to avoid 100 line cut off
  parameter int MUBI4W = prim_mubi_pkg::MuBi4Width;

  // functions

  // variables
  bit [NUM_INTERRUPTS-1:0] exp_intr;
  wakeups_t exp_wakeup_reasons;
  control_enables_t control_enables;
  logic low_power_hint;

  // package sources
  `include "pwrmgr_derived_rst_domain.sv"
  `include "pwrmgr_aon_item.sv"
  `include "pwrmgr_obs_items.sv"
  `include "pwrmgr_aon_agent_cfg.sv"

  typedef dv_base_sequencer #(.ITEM_T(pwrmgr_aon_item),
                              .CFG_T (pwrmgr_aon_agent_cfg)) pwrmgr_aon_sequencer;

  `include "pwrmgr_aon_rst_safe_driver.sv"
  `include "pwrmgr_aon_rst_safe_monitor.sv"
  `include "pwrmgr_aon_rst_safe_agent.sv"
  `include "pwrmgr_aon_seq.sv"

  `include "pwrmgr_fast_item.sv"
  `include "pwrmgr_fast_agent_cfg.sv"

  typedef dv_base_sequencer #(.ITEM_T(pwrmgr_fast_item),
                              .CFG_T (pwrmgr_fast_agent_cfg)) pwrmgr_fast_sequencer;

  `include "pwrmgr_fast_rst_safe_driver.sv"
  `include "pwrmgr_fast_rst_safe_monitor.sv"
  `include "pwrmgr_fast_rst_safe_agent.sv"
  `include "pwrmgr_fast_seq.sv"
  `include "pwrmgr_env_cfg.sv"
  `include "pwrmgr_env_cov.sv"
  `include "pwrmgr_virtual_sequencer.sv"
  `include "pwrmgr_scoreboard.sv"
  `include "pwrmgr_env.sv"

  // Reset-safe path. Built alongside the normal one above, which keeps working unchanged.
  `include "pwrmgr_rst_safe_env_cov.sv"
  `include "pwrmgr_rst_safe_virtual_sequencer.sv"
  `include "pwrmgr_rst_safe_scoreboard.sv"
  `include "pwrmgr_rst_safe_env.sv"
  `include "pwrmgr_vseq_list.sv"

endpackage
