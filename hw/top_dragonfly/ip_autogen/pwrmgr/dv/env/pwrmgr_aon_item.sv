// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Stimulus the always-on side of the device can be given: what the peripherals are asking for,
// and whether main power glitches.
//
// The AST power and clock handshake is not here. The device asks for its clocks and AST always
// answers, so that is peer behavior the driver performs on its own rather than something a test
// requests.
class pwrmgr_aon_item extends uvm_sequence_item;

  // Which of the three held levels this item is changing. The driver holds the rest, so a helper
  // sets its own input and says so, rather than restating every input on this side. Restating was
  // the older arrangement and it kept a second copy of the pins in the sequence, which went stale
  // the moment anything else moved them.
  rand bit change_wakeups;
  rand bit change_rstreqs;
  rand bit change_sw_rst_req;
  rand bit change_escalation;

  constraint change_c {
    soft change_wakeups == 1'b0;
    soft change_rstreqs == 1'b0;
    soft change_sw_rst_req == 1'b0;
  }

  // Peripheral wakeup requests, as the device sees them on wakeups_i.
  rand wakeups_t wakeups;

  // Peripheral reset requests, as the device sees them on rstreqs_i.
  rand resets_t rstreqs;

  // The software reset request that rstmgr forwards, as raw bits rather than the enumeration.
  // Only the true encoding requests a reset and every other value has to leave the device
  // alone, so the encodings that are not members of the enumeration are exactly what has to be
  // reachable, and a randomized enumeration would never produce them.
  rand bit [MUBI4W-1:0] sw_rst_req;

  // The alert handler escalating. Held until a test takes it away, because the device latches
  // what it does with it and only the reset it causes clears that.
  rand bit escalation_reset;

  // Taking the escalation clock away, so the device notices it can no longer receive escalations.
  // `esc_clk_stopped_cycles` is how long for: non-zero is a measured interruption the driver
  // spends and then undoes, zero means hold the clock away until a later item puts it back.
  rand bit          esc_clk_stopped;
  rand int unsigned esc_clk_stopped_cycles;

  // Holding the escalation reset instead, which the device notices the same way. There is no
  // count here: it is held until a later item releases it.
  rand bit          esc_rst_asserted;

  // Drop main power for long enough to be seen as a glitch. Off unless a test asks for it,
  // because a glitch destroys the operation in progress.
  rand bit power_glitch;

  // How long main power stays away, in slow clock cycles. The device registers a glitch from
  // the slow state machine, so the width is what decides whether it sees one at all.
  rand int unsigned glitch_width_slow_clks;

  // Idle unless a test asks otherwise. A reset request is not a harmless extra: the device
  // raises the wakeup interrupt only when it came out of low power because of a wakeup, so a
  // stray reset request turns a wakeup into a reset and the interrupt never appears, while the
  // recorded wakeup status and reasons still read exactly as expected.
  constraint rstreqs_c {soft rstreqs == '0;}

  constraint power_glitch_c {soft power_glitch == 1'b0;}
  constraint glitch_width_slow_clks_c {glitch_width_slow_clks inside {[1 : 6]};}
  constraint sw_rst_req_c {soft sw_rst_req == MuBi4False;}


  // Cycles to wait before applying this item. The offset belongs to the stimulus rather than
  // to a delay written into a sequence: a test that races two inputs against each other needs
  // to place them relative to one another, and the driver is what can do that on the clock the
  // input belongs to.
  rand int unsigned apply_delay_cycles;

  constraint apply_delay_cycles_c {soft apply_delay_cycles == 0;}

  constraint escalation_c {
    soft change_escalation == 1'b0;
    soft escalation_reset == 1'b0;
    soft esc_clk_stopped == 1'b0;
    soft esc_rst_asserted == 1'b0;
    soft esc_clk_stopped_cycles == 0;
  }

  `uvm_object_utils_begin(pwrmgr_aon_item)
    `uvm_field_int(apply_delay_cycles, UVM_DEFAULT)
    `uvm_field_int(change_wakeups, UVM_DEFAULT)
    `uvm_field_int(change_rstreqs, UVM_DEFAULT)
    `uvm_field_int(change_sw_rst_req, UVM_DEFAULT)
    `uvm_field_int(wakeups, UVM_DEFAULT)
    `uvm_field_int(rstreqs, UVM_DEFAULT)
    `uvm_field_int(escalation_reset, UVM_DEFAULT)
    `uvm_field_int(esc_clk_stopped, UVM_DEFAULT)
    `uvm_field_int(esc_rst_asserted, UVM_DEFAULT)
    `uvm_field_int(sw_rst_req, UVM_DEFAULT)
    `uvm_field_int(power_glitch, UVM_DEFAULT)
    `uvm_field_int(glitch_width_slow_clks, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_aon_item
