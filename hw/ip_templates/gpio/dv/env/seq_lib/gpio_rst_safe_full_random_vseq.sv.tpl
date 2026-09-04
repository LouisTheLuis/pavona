// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Every operation the block offers, chosen at random: driving the inputs, programming the
// output and output enable pairs, programming the interrupt registers, programming the filter,
// and bursts of register reads and writes.
//
// The legacy sequence tracked a predicted DATA_OUT and DATA_OE and adjusted every value it
// wrote so that the device and the testbench never drove one pin to different values. That
// bookkeeping is not needed here. The testbench only ever drives the pins with the device's
// output enables cleared, and lets go of them before anything that can set an output enable,
// so no pin has two drivers to reconcile.
//
// The legacy sequence also had an arm that reset the device itself. It is not carried over:
// reset belongs to reset_trigger_thread(), which owns it for the whole epoch.
class ${module_instance_name}_rst_safe_full_random_config_parameters
    extends ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_full_random_config_parameters)

  // Value written to whichever registers an operation selects.
  rand bit [TL_DW-1:0] reg_value;

  // Chooses between the filter register and DATA_IN in the miscellaneous arm.
  rand bit             misc_select;

  constraint op_select_c {
    op_select inside {[0:5]};
  }

  constraint reg_write_mask_c {
    reg_write_mask != '0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_full_random_config_parameters


class ${module_instance_name}_rst_safe_full_random_vseq
    extends ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_full_random_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task program_output_registers();
  extern protected task program_interrupt_registers();
  extern protected task program_misc_register();
endclass : ${module_instance_name}_rst_safe_full_random_vseq


function ${module_instance_name}_rst_safe_full_random_vseq::new(string name = "");
  super.new(name);
  ${module_instance_name}_rst_safe_config_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_full_random_config_parameters::get_type());
endfunction : new


task ${module_instance_name}_rst_safe_full_random_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    case (config_params.op_select)
      0:       drive_inputs();
      1:       program_output_registers();
      2:       program_interrupt_registers();
      3:       program_misc_register();
      4:       long_register_writes();
      default: long_register_reads();
    endcase
  end
endtask : main_thread


task ${module_instance_name}_rst_safe_full_random_vseq::program_output_registers();
  ${module_instance_name}_rst_safe_full_random_config_parameters params;
  `downcast(params, config_params)

  undrive_inputs();

  if (config_params.reg_write_mask[0]) begin
    csr_wr(.ptr(ral.direct_out), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[1]) begin
    csr_wr(.ptr(ral.masked_out_lower), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[2]) begin
    csr_wr(.ptr(ral.masked_out_upper), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[3]) begin
    csr_wr(.ptr(ral.direct_oe), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[4]) begin
    csr_wr(.ptr(ral.masked_oe_lower), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[5]) begin
    csr_wr(.ptr(ral.masked_oe_upper), .value(params.reg_value));
  end
endtask : program_output_registers


task ${module_instance_name}_rst_safe_full_random_vseq::program_interrupt_registers();
  ${module_instance_name}_rst_safe_full_random_config_parameters params;
  `downcast(params, config_params)

  if (config_params.reg_write_mask[0]) begin
    csr_wr(.ptr(ral.intr_enable), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[1]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_falling), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[2]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_rising), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[3]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvllow), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[4]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value(params.reg_value));
  end
  if (config_params.reg_write_mask[5]) begin
    // Write only, and the value written is an interrupt event for that cycle alone.
    csr_wr(.ptr(ral.intr_test), .value(params.reg_value));
  end
  // W1C, always exercised, so that the clear lands against whatever the arms above raised.
  csr_wr(.ptr(ral.intr_state), .value(params.csr_value));
endtask : program_interrupt_registers


task ${module_instance_name}_rst_safe_full_random_vseq::program_misc_register();
  ${module_instance_name}_rst_safe_full_random_config_parameters params;
  `downcast(params, config_params)

  if (params.misc_select) begin
    // The filter needs a stable input either side of the change, because a change taken while
    // a pin is mid transition tells nothing about which value the filter should have passed.
    drive_pins(.value(config_params.gpio_i),
               .drive_en('0),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(FILTER_CYCLES + 1));
    csr_wr(.ptr(ral.ctrl_en_input_filter), .value(params.reg_value));
    drive_pins(.value(config_params.gpio_i),
               .drive_en('0),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(FILTER_CYCLES + 1));
  end else begin
    // Hardware writes DATA_IN, so this checks that a software write to it is ignored.
    csr_wr(.ptr(ral.data_in), .value(params.reg_value));
  end
endtask : program_misc_register
