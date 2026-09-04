// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Stimulus for the testbench side of the GPIO pins and for the strap trigger.
//
// One item describes the complete pin state the testbench presents to the device, rather
// than an incremental change. A sequence that wants to move a single pin sends the whole
// vector with that one bit different, so the driver never has to remember what the previous
// item asked for and reset can discard an item without leaving the interface half updated.
class ${module_instance_name}_seq_item extends uvm_sequence_item;

  // Value presented on each pin the testbench drives.
  rand bit [NUM_GPIOS-1:0] gpio_i;
  // Which pins the testbench drives. A zero bit leaves that pin to the device output driver
  // or, if the device is not driving either, to the weak pull below.
  rand bit [NUM_GPIOS-1:0] gpio_i_oe;
  // Weak pulls. These model board topology rather than a driven value, so a sequence
  // normally sets them once per reset epoch in dut_init() and leaves them alone.
  rand bit [NUM_GPIOS-1:0] pullup_en;
  rand bit [NUM_GPIOS-1:0] pulldown_en;

  // Request a single-cycle strap_en pulse while this pin state is applied. The device
  // samples straps at most once per reset cycle, so a second pulse in the same epoch is
  // legal stimulus that must produce no second sample.
  rand bit strap_en_pulse;

  // Cycles to hold this pin state before the driver accepts the next item. Zero is legal
  // and produces a back-to-back change on the following edge.
  rand int unsigned hold_cycles;

  // Offset from the aligning clock edge at which the pin state is applied. Zero keeps the
  // change synchronous to the device clock. A non-zero value places the edge inside the
  // clock period, which is what the noise filter and synchronizer tests need in order to
  // present an input change that the device did not see coming on an edge.
  rand int unsigned drive_offset_ps;

  constraint hold_cycles_c {
    soft hold_cycles inside {[0:64]};
  }

  constraint drive_offset_ps_c {
    soft drive_offset_ps == 0;
  }

  constraint pullup_pulldown_c {
    // A pin cannot be pulled both ways. pins_if would give the pull up priority, so make the
    // stimulus say what it means instead of relying on that.
    (pullup_en & pulldown_en) == '0;
  }

  `uvm_object_utils_begin(${module_instance_name}_seq_item)
    `uvm_field_int(gpio_i,          UVM_DEFAULT)
    `uvm_field_int(gpio_i_oe,       UVM_DEFAULT)
    `uvm_field_int(pullup_en,       UVM_DEFAULT)
    `uvm_field_int(pulldown_en,     UVM_DEFAULT)
    `uvm_field_int(strap_en_pulse,  UVM_DEFAULT)
    `uvm_field_int(hold_cycles,     UVM_DEFAULT)
    `uvm_field_int(drive_offset_ps, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : ${module_instance_name}_seq_item
