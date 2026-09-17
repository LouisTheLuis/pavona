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

  // clk enable disable delay How many bus clock cycles this top fits inside one always-on cycle,
  // taken from the clock frequencies it is built with. The two tops differ by a large factor, so
  // anything counted in always-on cycles covers that many times more bus work on one than on the
  // other. Rounded up, so a top whose frequencies do not divide exactly is modeled with an always-
  // on cycle at least as long as the real one.
  parameter uint BusCyclesPerAonCycle = 120;

  // How long one low power operation takes, in always-on cycles: about twenty three cycles of
  // handshaking between the two domains plus about fifty bus cycles of work, and the bus part costs
  // fewer always-on cycles the wider the ratio. A reset meant to land inside the operation is
  // placed against this rather than a count taken on one top. The bus part is rounded up to a whole
  // always-on cycle, since truncating it to zero would claim the operation is shorter than it is.
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
    PwrmgrAonGlitch,
    PwrmgrAonClkValid
  } pwrmgr_aon_obs_kind_e;

  typedef enum int {
    PwrmgrFastActive,
    PwrmgrFastLowPower,
    PwrmgrFastStrap,
    PwrmgrFastIntr,
    PwrmgrFastPeerReq,
    PwrmgrFastHwWrite,
    PwrmgrFastFsmState,
    PwrmgrFastStim,
    PwrmgrFastEscTimeout
  } pwrmgr_fast_obs_kind_e;

  // How many past values of a hardware written register are kept for checking a read. A read is
  // answered from whatever the device holds at that instant, so it is checked against several.
  parameter uint VolatileReadHistoryDepth = 16;

  // How many flops the device puts between a driven input and the logic that reads it. The
  // processor sleeping, the flash idle and the otp response cross through a two flop synchronizer,
  // so a decision was taken on the value from this many cycles earlier. The lifecycle idle has none
  // and is read directly.
  parameter uint SyncFlops = 2;

  // Cycles a crossing can take beyond those flops. The delay elements inside `prim_flop_2sync` hold
  // a change back one further cycle when the clock domain crossing instrumentation is on, and each
  // input crosses on its own, so the value the device acted on came from somewhere in a window
  // rather than from one cycle. Predictions span the window so they hold either way.
  parameter uint CdcJitterCycles = 1;

  // How many driven changes to keep so a prediction can ask what the device could see. Only a
  // few cycles are ever looked back over, but stimulus changes arrive in bursts.
  parameter uint StimHistoryDepth = 32;

  // How long the invalid state tests keep asking a wedged device to act. The reset that frees it is
  // scheduled up to 60 delay steps in and each round spends four, so this covers the range.
  parameter uint InvalidStateHoldRounds = 20;

  // Delay steps spent between one piece of stimulus and the next while the device is wedged.
  parameter uint InvalidStateHoldSteps = 1;

  // How long to take the escalation clock away in the round that checks a short interruption is
  // tolerated, kept well short of the device's own count. This is the magnitude of the stimulus,
  // not a wait.
  parameter uint EscTimeoutSafeCycles = pwrmgr_pkg::EscTimeOutCnt / 4;

  // When the escalation path has been broken for this long the device raises its fatal alert. It is
  // the device's own count and not a cycle more: an expectation is met only by an alert arriving
  // after it, so announcing late leaves it standing against an alert already gone.
  parameter uint EscTimeoutDetectCycles = pwrmgr_pkg::EscTimeOutCnt;

  // Giving the escalation clock back does not clear the device's count. `prim_clock_timeout` clears
  // on an acknowledgment `prim_sync_reqack` returns, a round trip through two synchronizers, so
  // until the escalation clock has run for it the count stands where the interruption left it. This
  // bounds that round trip rather than reproducing it: a count already cleared in the device may
  // still be standing here, but it must not clear here while the device is still counting.
  parameter uint EscTimeoutAckCycles = 8;

  // How long a sequence waits for something the device announces before giving up. Long enough for
  // a slow domain crossing and a full boot, short enough to fail with a clear message instead of
  // the phase timeout. It lives here because the stress wrapper waits on the same announcements.
  // How long the framework waits for the fatal alert after a fault is predicted. It has to outlast
  // the device resetting itself, which clears the fault status and withdraws the alert, and that
  // walk is paced by the always-on clock. Counted in bus cycles, so it grows with the ratio.
  parameter uint FatalAlertMaxDelay = 500 * BusCyclesPerAonCycle / 4;

  parameter uint FastObsTimeoutAonCycles = 2_000;


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
