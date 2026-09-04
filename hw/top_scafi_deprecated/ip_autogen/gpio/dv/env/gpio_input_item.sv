// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The device's input path, both ends of it, sampled at one clock edge and published when
// either end changes.
//
// Both ends travel in one item on one port so that a checker cannot process them out of
// order. They are sampled by one clocking block in one process, so they cannot be observed
// out of step either. The filter model predicts the filtered end from the raw end and is
// checked against it; everything downstream of the filter is then predicted from the checked
// filtered value rather than from a second reconstruction of it.
class gpio_input_item extends uvm_sequence_item;

  // The input the device sampled, before its filter.
  bit [NUM_GPIOS-1:0] raw_in;

  // The same input after the synchronizer and the filter.
  bit [NUM_GPIOS-1:0] data_in;

  // Edges of the filtered input. These are the events the device's interrupt logic and its
  // input period counters key off, so a consumer does not have to derive them and risk
  // deriving them differently.
  bit [NUM_GPIOS-1:0] rising;
  bit [NUM_GPIOS-1:0] falling;

  // Number of clock edges completed in this reset epoch when these values were sampled. The
  // values are those settled immediately before edge `epoch_cycle`, so they are the result of
  // edges up to and including `epoch_cycle - 1`, and `raw_in` is the value edge
  // `epoch_cycle` will act on.
  longint unsigned epoch_cycle;

  `uvm_object_utils_begin(gpio_input_item)
    `uvm_field_int(raw_in,      UVM_DEFAULT)
    `uvm_field_int(data_in,     UVM_DEFAULT)
    `uvm_field_int(rising,      UVM_DEFAULT)
    `uvm_field_int(falling,     UVM_DEFAULT)
    `uvm_field_int(epoch_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : gpio_input_item
