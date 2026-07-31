// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe specialization for the I2C sequencer. The monitor publishes mutable
// in-progress transfer handles into the two inherited FIFOs. Those handles belong
// to the reset epoch in which they were observed and must not survive a reset.
class i2c_rst_safe_sequencer extends i2c_sequencer;
  `uvm_component_utils(i2c_rst_safe_sequencer)
  `uvm_component_new

  virtual function void stop_sequences();
    super.stop_sequences();
    controller_mode_in_progress_fifo.flush();
    target_mode_in_progress_fifo.flush();
  endfunction : stop_sequences
endclass : i2c_rst_safe_sequencer
