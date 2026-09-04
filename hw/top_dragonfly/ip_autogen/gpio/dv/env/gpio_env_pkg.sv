// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package gpio_env_pkg;
  // dep packages
  import uvm_pkg::*;
  import top_pkg::*;
  import dv_utils_pkg::*;
  import csr_utils_pkg::*;
  import dv_base_reg_pkg::*;
  import tl_agent_pkg::*;
  import dv_lib_pkg::*;
  // reset_seq and delay_seq, used by the reset-safe sequences.
  import clk_rst_agent_pkg::*;
  import cip_base_pkg::*;
  import gpio_ral_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // Pin count and input period counter count come from the register package the RTL is
  // built from, so a change to the instance configuration cannot leave the testbench
  // describing a different device than the one elaborated.
  parameter uint NUM_GPIOS     = gpio_reg_pkg::NumIOs;
  parameter uint NUM_INP_PRD_CNT = gpio_reg_pkg::NumInpPeriodCounters;
  // Threshold of prim_filter_ctr, which counts to an all-ones 4-bit value.
  parameter uint FILTER_CYCLES = 16;

  // Values kept per hardware written register so that a read can be checked against what the
  // register held around the access. The register content and the bus access reach the
  // scoreboard on different analysis ports with no ordering between them, so the window has to
  // cover both the updates the access spans and the amount by which the probe leads it.
  //
  // Sized from the span the scoreboard measures for every read, matched or not, which reached
  // seven on the sequences that move the pins fastest, plus a lead of one. Eight is therefore
  // the requirement and this is one doubling above it. The failure message reports the span,
  // so a sequence that outgrows this says so rather than just failing.
  parameter uint VolatileReadHistoryDepth = 16;
  // No. of alerts
  parameter uint NUM_ALERTS = 1;
  parameter string LIST_OF_ALERTS[NUM_ALERTS] = {"fatal_fault"};

  typedef virtual pins_if #(NUM_GPIOS) gpio_vif;
  typedef virtual gpio_straps_if straps_vif;
  typedef virtual gpio_probe_if gpio_probe_vif;
  typedef class gpio_env_cfg;
  typedef class gpio_env_cov;
  typedef class gpio_agent_cfg;

  // Names one of the monitor's observation ports. The monitor writes this immediately after
  // it writes the port it names, giving a consumer a single ordered account of everything the
  // probe saw. Without it, observations made in one pass sit in separate FIFOs and whichever
  // consumer the scheduler happens to run first decides the order they are processed in.
  typedef enum {
    GpioProbeInput,
    GpioProbeIntr,
    GpioProbeStraps,
    GpioProbeHwWrite,
    GpioProbeOutput
  } gpio_probe_kind_e;
  typedef cip_base_virtual_sequencer #(gpio_env_cfg, gpio_env_cov) gpio_virtual_sequencer;

  // structure to indicate gpio pin transition and type of transition
  // transition_occurred: 1-yes, 0-no
  // is_rising_edge: 1-rising edge transition, 0-falling edge transition
  typedef struct packed {
    bit transition_occurred;
    bit is_rising_edge;
  } gpio_transition_t;

  // structure to indicate whether or not register update is due for particular gpio register
  // needs_update: 1-update is due, 0-update is not due
  // reg_value: value to be updated when update is due
  // eval_time: time stamp of event, which triggered interrupt update
  typedef struct packed {
    bit needs_update;
    bit [TL_DW-1:0] reg_value;
    time eval_time;
  } gpio_reg_update_due_t;

  // package sources
  `include "gpio_env_cfg.sv"
  `include "gpio_env_cov.sv"

  // Reset-safe agent. The items come first because the configuration, driver, monitor and
  // sequencer all refer to them.
  `include "gpio_seq_item.sv"
  `include "gpio_straps_item.sv"
  `include "gpio_intr_item.sv"
  `include "gpio_input_item.sv"
  `include "gpio_hw_write_item.sv"
  `include "gpio_output_item.sv"
  `include "gpio_agent_cfg.sv"
  `include "gpio_sequencer.sv"
  `include "gpio_rst_safe_driver.sv"
  `include "gpio_rst_safe_monitor.sv"
  `include "gpio_rst_safe_agent.sv"

  `include "gpio_reference_model.sv"
  `include "gpio_rst_safe_env_cov.sv"
  `include "gpio_scoreboard.sv"
  `include "gpio_rst_safe_scoreboard.sv"
  `include "gpio_rst_safe_virtual_sequencer.sv"
  `include "gpio_rst_safe_env.sv"
  `include "gpio_env.sv"
  `include "gpio_vseq_list.sv"
endpackage
