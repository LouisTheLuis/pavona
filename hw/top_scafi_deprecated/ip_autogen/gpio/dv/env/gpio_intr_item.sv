// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A passive observation of the interrupt output pins, published when they change.
//
// The block drives one interrupt per GPIO pin, so only the low NUM_GPIOS bits of the shared
// interrupt interface belong to this device and only those are published. Edges are carried
// alongside the level because an interrupt that is asserted, cleared and asserted again
// between two observations of the same level is a different history from one that never
// moved, and the checker needs to tell them apart.
class gpio_intr_item extends uvm_sequence_item;

  bit [NUM_GPIOS-1:0] pins;
  bit [NUM_GPIOS-1:0] rising;
  bit [NUM_GPIOS-1:0] falling;

  // Cycles since this reset epoch began, on the same count as gpio_input_item.
  // The interrupt is a flop of the filtered input state, so relating an interrupt edge to the
  // pin change that caused it is a cycle level question and needs a shared count to answer.
  longint unsigned epoch_cycle;

  `uvm_object_utils_begin(gpio_intr_item)
    `uvm_field_int(pins,        UVM_DEFAULT)
    `uvm_field_int(rising,      UVM_DEFAULT)
    `uvm_field_int(falling,     UVM_DEFAULT)
    `uvm_field_int(epoch_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : gpio_intr_item
