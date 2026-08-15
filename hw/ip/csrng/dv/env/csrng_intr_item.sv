// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A passive observation of an interrupt-pin value change. Runtime interrupt
// state is transported as a monitor transaction rather than sampled from the
// interface by a layer above the monitor.
class csrng_intr_item extends uvm_sequence_item;
  bit [NumCsrngIntr-1:0] pins;
  bit [NumCsrngIntr-1:0] rising;
  bit [NumCsrngIntr-1:0] falling;

  `uvm_object_utils_begin(csrng_intr_item)
    `uvm_field_int(pins, UVM_DEFAULT)
    `uvm_field_int(rising, UVM_DEFAULT)
    `uvm_field_int(falling, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new
endclass : csrng_intr_item
