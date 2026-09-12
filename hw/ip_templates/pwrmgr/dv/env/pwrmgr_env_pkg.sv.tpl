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
% for clk in reversed(src_clks):
  % if clk == 'usb':
    logic usb_clk_en_active;
    logic usb_clk_en_lp;
  % else:
    logic ${clk}_clk_en;
  % endif
% endfor
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
