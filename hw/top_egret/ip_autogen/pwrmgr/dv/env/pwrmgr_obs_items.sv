// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// What the monitors publish, one type per kind of thing the device does.
//
// Each publication is an event rather than a sample of everything: the device announced that the
// processor may run, or a peripheral asked for a wakeup, or the interrupt was raised. A consumer
// waits for the event it cares about and is handed exactly that, instead of scanning a stream of
// states for one that happens to match.
//
// Every item carries a free running edge count of its own clock, and every publication is also
// named on the monitor's direction port, so the order of events across the different ports is
// recoverable. That ordering is what decides races the device itself resolves, most of all
// whether a wakeup or a reset request arrived first.

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
  longint unsigned clk_count;

  `uvm_object_utils_begin(pwrmgr_reset_req_item)
    `uvm_field_int(rstreqs, UVM_DEFAULT)
    `uvm_field_enum(mubi4_t, sw_rst_req, UVM_DEFAULT)
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
