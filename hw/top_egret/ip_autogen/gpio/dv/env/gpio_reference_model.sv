// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reference model for the gpio input path and its consequences.
//
// It holds the predictions the scoreboard compares observations against. Keeping it out of
// the scoreboard leaves that class a set of FIFO workers and gives the build-time
// elaboration parameters a single consumer.
//
// The model contains no clock period and consults no simulation time. It is advanced in
// clock cycles by observations that carry an epoch cycle, so changing the elaboration moves
// the observations rather than invalidating the model.
class gpio_reference_model extends uvm_object;
  `uvm_object_utils(gpio_reference_model)

  // prim_filter_ctr is instantiated with CntWidth 4 and thresh_i tied to all ones, so the
  // difference counter saturates at 15. FILTER_CYCLES is the window that produces, one more
  // than the threshold because the counter starts from zero.

  // Cycles of constant input after which the whole input path is in steady state: two for
  // the synchronizer to flush, FILTER_CYCLES for the difference counter to saturate, and a
  // margin. Advancing further than this with an unchanging input cannot change any state,
  // which is what makes the clamp in advance() exact rather than approximate.

  // Reported INTR_STATE changes kept for the interrupt pin lookup. The pin is one flop behind
  // the register, so a lookup only ever reaches back a cycle; the depth is for the case where
  // several changes carry the same or adjacent stamps.

  // Build-time elaboration of the device being modelled, set by the scoreboard at build.
  bit gpio_as_hw_straps_en;


  extern function new(string name = "");
  extern virtual function void reset();


  // Strap latch. The device samples its filtered input as straps at most once per reset
  // cycle, on the first cycle strap_en is high while the valid bit is clear, and holds the
  // result until reset. `sample_trigger` in the design is `strap_en && !valid`, so the valid
  // bit is both the output of the latch and the thing that prevents a second one.
  bit                 straps_valid;
  bit [NUM_GPIOS-1:0] straps_data;

  extern virtual function void commit_straps(bit [NUM_GPIOS-1:0] data);

  // The device's output drive, maintained from the writes that change it. cio_gpio_q and
  // cio_gpio_en_q are updated only by a write to their register, with DIRECT taking priority
  // over the upper half and the upper half over the lower, and a masked write leaving the
  // bits its mask does not select alone.
  bit [NUM_GPIOS-1:0] data_out;
  bit [NUM_GPIOS-1:0] data_oe;

  extern virtual function void apply_out_write(string reg_name, bit [TL_DW-1:0] wdata);

endclass : gpio_reference_model


function gpio_reference_model::new(string name = "");
  super.new(name);
endfunction : new


function void gpio_reference_model::reset();
  // Every flop in the input path clears at reset: both synchronizer stages, the filter's
  // stored value, its input flop and its difference counter.
  // prim_intr_hw clears INTR_STATE at reset, so a pending interrupt does not survive into
  // the next epoch and neither does the model's idea of one.
  // Reset clears the valid bit, which is what re-arms the strap latch. Without that the
  // feature would sample once in the life of the device rather than once per reset.
  straps_valid          = 1'b0;
  straps_data           = '0;
  // Both output registers clear at reset, so the device drives nothing until software asks
  // it to.
  data_out              = '0;
  data_oe               = '0;
endfunction : reset




function void gpio_reference_model::apply_out_write(
    string reg_name, bit [TL_DW-1:0] wdata);
  bit [15:0] data = wdata[15:0];
  bit [15:0] mask = wdata[31:16];

  case (reg_name)
    "direct_out": data_out = wdata[NUM_GPIOS-1:0];
    "direct_oe":  data_oe  = wdata[NUM_GPIOS-1:0];
    "masked_out_lower": data_out[15:0] = (mask & data) | (~mask & data_out[15:0]);
    "masked_out_upper": data_out[NUM_GPIOS-1:16] =
        (mask & data) | (~mask & data_out[NUM_GPIOS-1:16]);
    "masked_oe_lower": data_oe[15:0] = (mask & data) | (~mask & data_oe[15:0]);
    "masked_oe_upper": data_oe[NUM_GPIOS-1:16] =
        (mask & data) | (~mask & data_oe[NUM_GPIOS-1:16]);
    default: ;
  endcase
endfunction : apply_out_write


function void gpio_reference_model::commit_straps(
    bit [NUM_GPIOS-1:0] data);
  straps_valid = 1'b1;
  straps_data  = data;
endfunction : commit_straps
