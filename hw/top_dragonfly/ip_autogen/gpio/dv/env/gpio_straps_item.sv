// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A passive observation of the sampled strap broadcast.
//
// The device samples its inputs as straps at most once per reset cycle, on the first cycle
// where strap_en is high, and holds the result until reset. This item is published when the
// broadcast changes, so at most one carrying valid is expected per reset epoch. A second one
// in the same epoch is a testbench or device error rather than a repeat observation.
class gpio_straps_item extends uvm_sequence_item;

  bit [NUM_GPIOS-1:0] data;
  bit                 valid;

  // Set when the item reports the sample being requested rather than the broadcast changing.
  bit                 trigger;

  // Cycles since this reset epoch began, on the same count as gpio_input_item,
  // so a checker can relate the sample to the pin state that produced it.
  longint unsigned epoch_cycle;

  `uvm_object_utils_begin(gpio_straps_item)
    `uvm_field_int(data,        UVM_DEFAULT)
    `uvm_field_int(valid,       UVM_DEFAULT)
    `uvm_field_int(trigger,     UVM_DEFAULT)
    `uvm_field_int(epoch_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : gpio_straps_item
