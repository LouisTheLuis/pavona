// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A change of a software-visible register that the hardware maintains, observed at the
// register rather than reconstructed from the bus.
//
// One item is one change: the register, the complete value it now holds, and the cycle from
// which it holds it. Where one enable commits more than one register, as the strap latch
// does, the group travels as one item because it is one event.
//
// INTR_STATE is observed as stored content because prim_subreg_arb resolves a same-cycle
// software write against a hardware set, and the stored value is the outcome of that
// arbitration rather than one of its inputs. The others are observed at their hardware write
// enable, which for those registers fires only when something actually happened.
//
// A consumer must check the value against a prediction built from architectural inputs
// before using it to predict a RAL field. Without that ordering, a checker fed by these
// items would be confirming the device against itself.
typedef enum {
  GpioHwWriteStraps,
  GpioHwWriteInpPrdCntVal
} ${module_instance_name}_hw_write_kind_e;

class ${module_instance_name}_hw_write_item extends uvm_sequence_item;

  ${module_instance_name}_hw_write_kind_e kind;

  // Index within a multireg. Zero for the registers that are not one.
  int unsigned index;

  // The complete committed value, not a delta.
  bit [TL_DW-1:0] value;

  // Second half of an atomic group. Used by the strap latch, where the data and the valid
  // bit commit together on one enable.
  bit aux_valid;

  // Cycle within this reset epoch at which the value took effect. The enable was high before
  // edge N and the register holds this value from cycle N onward.
  longint unsigned epoch_cycle;

  `uvm_object_utils_begin(${module_instance_name}_hw_write_item)
    `uvm_field_enum(${module_instance_name}_hw_write_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(index,       UVM_DEFAULT)
    `uvm_field_int(value,       UVM_DEFAULT)
    `uvm_field_int(aux_valid,   UVM_DEFAULT)
    `uvm_field_int(epoch_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  `uvm_object_new

endclass : ${module_instance_name}_hw_write_item
