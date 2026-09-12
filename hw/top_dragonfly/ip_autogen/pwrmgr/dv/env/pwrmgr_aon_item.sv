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

  // Peripheral wakeup requests, as the device sees them on wakeups_i.
  rand wakeups_t wakeups;

  // Peripheral reset requests, as the device sees them on rstreqs_i.
  rand resets_t rstreqs;

  // The software reset request that rstmgr forwards. Only MuBi4True requests a reset; the
  // other values are the interesting negative cases, so they are worth reaching.
  rand mubi4_t sw_rst_req;

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

  `uvm_object_utils_begin(pwrmgr_aon_item)
    `uvm_field_int(wakeups, UVM_DEFAULT)
    `uvm_field_int(rstreqs, UVM_DEFAULT)
    `uvm_field_enum(mubi4_t, sw_rst_req, UVM_DEFAULT)
    `uvm_field_int(power_glitch, UVM_DEFAULT)
    `uvm_field_int(glitch_width_slow_clks, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : pwrmgr_aon_item
