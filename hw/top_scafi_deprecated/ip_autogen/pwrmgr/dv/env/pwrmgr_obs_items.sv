// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// What the monitors publish, one type per kind of thing the device does.
//
// Each publication is an event rather than a sample: a consumer waits for the event it cares about
// and is handed exactly that, instead of scanning a stream of states.
//
// Every item carries a free running edge count of its own clock, and every publication is named on
// the monitor's direction port, so the order of events across ports is recoverable. That ordering
// decides races the device itself resolves, above all whether a wakeup or a reset request came
// first.

// The device announcing that the processor may run, or that it may not.
class pwrmgr_active_item extends uvm_sequence_item;
  lc_ctrl_pkg::lc_tx_t fetch_en;
  longint unsigned     clk_count;

  `uvm_object_utils_begin(pwrmgr_active_item)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_active_item


// One bit the device asserted or released: low power entry, the strap sample, the wakeup
// interrupt, or main power going away. Which one is named by the port it arrives on.
class pwrmgr_flag_item extends uvm_sequence_item;
  logic            value;
  longint unsigned clk_count;

  `uvm_object_utils_begin(pwrmgr_flag_item)
    `uvm_field_int(value, UVM_DEFAULT)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_flag_item


// What the peripherals are asking the device for.
class pwrmgr_wakeup_item extends uvm_sequence_item;
  wakeups_t        wakeups;
  longint unsigned clk_count;

  `uvm_object_utils_begin(pwrmgr_wakeup_item)
    `uvm_field_int(wakeups, UVM_DEFAULT)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_wakeup_item


class pwrmgr_reset_req_item extends uvm_sequence_item;
  resets_t         rstreqs;
  mubi4_t          sw_rst_req;

  // The alert handler escalating. Reported here with the other things that can make the device
  // reset, so the checker can account for a reset it sees.
  bit              escalation;
  longint unsigned clk_count;

  `uvm_object_utils_begin(pwrmgr_reset_req_item)
    `uvm_field_int(rstreqs, UVM_DEFAULT)
    `uvm_field_enum(mubi4_t, sw_rst_req, UVM_DEFAULT)
    `uvm_field_int(escalation, UVM_DEFAULT)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_reset_req_item


// What the device is asking AST for: power and the clocks.
class pwrmgr_ast_req_item extends uvm_sequence_item;
  pwrmgr_pkg::pwr_ast_req_t ast_req;
  longint unsigned          clk_count;

  `uvm_object_utils_begin(pwrmgr_ast_req_item)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_ast_req_item


// What the device is asking its fast side peers for: resets from rstmgr, clocks from clkmgr,
// and initialization from otp and lifecycle.
class pwrmgr_peer_req_item extends uvm_sequence_item;
  pwrmgr_pkg::pwr_rst_req_t rst_req;
  pwrmgr_pkg::pwr_clk_req_t clk_req;
  lc_ctrl_pkg::pwr_lc_req_t lc_req;
  pwrmgr_pkg::pwr_otp_req_t otp_req;
  longint unsigned          clk_count;

  `uvm_object_utils_begin(pwrmgr_peer_req_item)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_peer_req_item


// A register the device wrote itself, reported with the value it committed. The checker compares
// its own prediction against this and only then updates the register model, because a register
// software never wrote cannot be checked against the mirror until the model has agreed with the
// device about what the device just did.
// The state machine's state, published when it changes. What the invalid state test checks is a
// property of this sequence of states, so it is reported as transactions like anything else.
class pwrmgr_fsm_item extends uvm_sequence_item;

  pwrmgr_pkg::fast_pwr_state_e state;
  longint unsigned             clk_count;

  `uvm_object_utils_begin(pwrmgr_fsm_item)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_fsm_item


// What the testbench is presenting to the fast side. The device decides how to abandon a low
// power transition from these, so the checker needs them to predict what it will record.
class pwrmgr_fast_stim_item extends uvm_sequence_item;

  // A reset asked for by the debug module. One of the things that can make the device reset.
  bit ndmreset_req;

  bit core_sleeping;
  bit flash_idle;
  bit otp_idle;
  bit lc_idle;
  longint unsigned clk_count;

  `uvm_object_utils_begin(pwrmgr_fast_stim_item)
    `uvm_field_int(ndmreset_req, UVM_DEFAULT)
    `uvm_field_int(core_sleeping, UVM_DEFAULT)
    `uvm_field_int(flash_idle, UVM_DEFAULT)
    `uvm_field_int(otp_idle, UVM_DEFAULT)
    `uvm_field_int(lc_idle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_fast_stim_item


class pwrmgr_hw_write_item extends uvm_sequence_item;
  wakeups_t                                     wake_status;

  longint unsigned                              clk_count;

  `uvm_object_utils_begin(pwrmgr_hw_write_item)
    `uvm_field_int(wake_status, UVM_DEFAULT)
    `uvm_field_int(clk_count, UVM_DEFAULT)
  `uvm_object_utils_end
  `uvm_object_new
endclass : pwrmgr_hw_write_item
