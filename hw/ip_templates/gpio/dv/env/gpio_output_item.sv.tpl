// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The device's output drive, published when it changes.
//
// This is the architectural output: what the block drives and on which pins it enables its
// driver. It is deliberately not the resolved value of the bidirectional net, which is the
// combination of this, whatever the testbench is driving, and the board's pulls. Checking a
// prediction of one contributor against the sum of three would mean guessing which of them
// moved.
class ${module_instance_name}_output_item extends uvm_sequence_item;

  bit [NUM_GPIOS-1:0] data_out;
  bit [NUM_GPIOS-1:0] data_oe;

  // Number of clock edges completed in this reset epoch when these values were sampled.
  longint unsigned epoch_cycle;

  `uvm_object_utils_begin(${module_instance_name}_output_item)
    `uvm_field_int(data_out,    UVM_DEFAULT)
    `uvm_field_int(data_oe,     UVM_DEFAULT)
    `uvm_field_int(epoch_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : ${module_instance_name}_output_item
