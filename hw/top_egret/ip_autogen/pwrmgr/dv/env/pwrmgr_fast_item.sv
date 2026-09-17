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
  // What this item changes. A pin the item says nothing about keeps the value the driver last
  // drove, so an item about one thing does not restate the others. Without this every item
  // carried the whole pin state from the sequence's own copy of it, and a reset that cleared the
  // pins left that copy untouched, so the next item put the old values back.
  rand bit change_core_sleeping;
  rand bit change_ndmreset_req;
  rand bit change_idles;
  rand bit change_lc;
  rand bit change_rom;

  rand bit core_sleeping;

  // A non-debug module reset request from the debug module.
  rand bit ndmreset_req;

  // The non-volatile blocks are idle. Low power is aborted if any of them is busy, so these
  // decide between a completed transition and an abort.
  rand bit flash_idle;
  rand bit otp_idle;
  rand bit lc_idle;

  // Start the processor executing again just after the device commits to a low power
  // transition, so it abandons it. The driver places this against the device's own progress,
  // because it owns both the input and the answer the device is waiting for.
  rand bit wake_processor_on_entry;

  // Send the state machine to its invalid state when it reaches a named state, to check it
  // wedges there rather than carrying on. The sequence names the state; waiting for it is the
  // driver's job, because the driver is what owns this interface.
  rand bit                          force_fsm_invalid;
  rand pwrmgr_pkg::fast_pwr_state_e invalid_at_state;

  // The lifecycle broadcast. These qualify whether a failed rom check still lets the device
  // reach active.
  // Raw bits rather than the enumeration. The corruption test sends encodings that are not
  // members of it, and a randomized enumeration can never produce those.
  rand bit [lc_ctrl_pkg::TxWidth-1:0] lc_hw_debug_en;
  rand bit [lc_ctrl_pkg::TxWidth-1:0] lc_dft_en;

  // What each rom check reports. done gates the transition to active; good decides whether the
  // device treats the rom as trustworthy.
  rand mubi4_t rom_done[pwrmgr_reg_pkg::NumRomInputs];
  rand mubi4_t rom_good[pwrmgr_reg_pkg::NumRomInputs];

  constraint change_c {
    soft change_core_sleeping == 1'b0;
    soft change_ndmreset_req  == 1'b0;
    soft change_idles         == 1'b0;
    soft change_lc            == 1'b0;
    soft change_rom           == 1'b0;
  }

  constraint core_sleeping_c {soft core_sleeping == 1'b0;}
  constraint ndmreset_req_c {soft ndmreset_req == 1'b0;}
  constraint force_fsm_invalid_c {soft force_fsm_invalid == 1'b0;}
  constraint wake_processor_on_entry_c {soft wake_processor_on_entry == 1'b0;}
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

  // Cycles to wait before applying this item. The offset belongs to the stimulus rather than
  // to a delay written into a sequence: a test that races two inputs against each other needs
  // to place them relative to one another, and the driver is what can do that on the clock the
  // input belongs to.
  rand int unsigned apply_delay_cycles;

  constraint apply_delay_cycles_c {soft apply_delay_cycles == 0;}

  `uvm_object_utils_begin(pwrmgr_fast_item)
    `uvm_field_int(apply_delay_cycles, UVM_DEFAULT)
    `uvm_field_int(change_core_sleeping, UVM_DEFAULT)
    `uvm_field_int(change_ndmreset_req, UVM_DEFAULT)
    `uvm_field_int(change_idles, UVM_DEFAULT)
    `uvm_field_int(change_lc, UVM_DEFAULT)
    `uvm_field_int(change_rom, UVM_DEFAULT)
    `uvm_field_int(core_sleeping, UVM_DEFAULT)
    `uvm_field_int(ndmreset_req, UVM_DEFAULT)
    `uvm_field_int(flash_idle, UVM_DEFAULT)
    `uvm_field_int(otp_idle, UVM_DEFAULT)
    `uvm_field_int(lc_idle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_fast_item
