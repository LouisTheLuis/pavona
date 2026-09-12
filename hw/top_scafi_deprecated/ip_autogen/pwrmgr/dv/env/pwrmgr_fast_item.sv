// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Stimulus for the fast side of the device: what the processor and the non-volatile blocks are
// doing, what the rom check reports, and the lifecycle broadcast.
//
// The rstmgr, clkmgr, otp and lifecycle handshakes are not here. Those peers always answer, so
// the driver performs them without being asked.
class pwrmgr_fast_item extends uvm_sequence_item;

  // The processor is in wait for interrupt. Low power cannot begin until it is.
  rand bit core_sleeping;

  // A non-debug module reset request from the debug module.
  rand bit ndmreset_req;

  // The non-volatile blocks are idle. Low power is aborted if any of them is busy, so these
  // decide between a completed transition and an abort.
  rand bit flash_idle;
  rand bit otp_idle;
  rand bit lc_idle;

  // The lifecycle broadcast. These qualify whether a failed rom check still lets the device
  // reach active.
  rand lc_ctrl_pkg::lc_tx_t lc_hw_debug_en;
  rand lc_ctrl_pkg::lc_tx_t lc_dft_en;

  // What each rom check reports. done gates the transition to active; good decides whether the
  // device treats the rom as trustworthy.
  rand mubi4_t rom_done[pwrmgr_reg_pkg::NumRomInputs];
  rand mubi4_t rom_good[pwrmgr_reg_pkg::NumRomInputs];

  constraint core_sleeping_c {soft core_sleeping == 1'b0;}
  constraint ndmreset_req_c {soft ndmreset_req == 1'b0;}
  constraint idle_c {
    soft flash_idle == 1'b1;
    soft otp_idle == 1'b1;
    soft lc_idle == 1'b1;
  }
  constraint lc_c {
    soft lc_hw_debug_en == lc_ctrl_pkg::Off;
    soft lc_dft_en == lc_ctrl_pkg::Off;
  }
  constraint rom_c {
    foreach (rom_done[i]) soft rom_done[i] == MuBi4True;
    foreach (rom_good[i]) soft rom_good[i] == MuBi4True;
  }

  `uvm_object_utils_begin(pwrmgr_fast_item)
    `uvm_field_int(core_sleeping, UVM_DEFAULT)
    `uvm_field_int(ndmreset_req, UVM_DEFAULT)
    `uvm_field_int(flash_idle, UVM_DEFAULT)
    `uvm_field_int(otp_idle, UVM_DEFAULT)
    `uvm_field_int(lc_idle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_fast_item
