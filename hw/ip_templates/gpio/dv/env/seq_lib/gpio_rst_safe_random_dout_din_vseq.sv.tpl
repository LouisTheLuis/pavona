// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Randomly either drives the inputs and reads them back, or programs the output and output
// enable registers, direct and masked.
//
// The legacy sequence chose between the two with `randcase` and picked which registers to
// write with `$urandom_range`, neither of which replays from a seed. Those choices are now
// constrained random members of the parameter object.
class ${module_instance_name}_rst_safe_random_dout_din_config_parameters
    extends ${module_instance_name}_rst_safe_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_random_dout_din_config_parameters)

  // Two arms: drive the inputs, or program the outputs.
  constraint op_select_c {
    op_select inside {[0:1]};
  }

  // At least one register per programming operation, or the arm does nothing.
  constraint reg_write_mask_c {
    reg_write_mask != '0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_random_dout_din_config_parameters


class ${module_instance_name}_rst_safe_random_dout_din_vseq
    extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_random_dout_din_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_inputs_and_read();
  extern protected task program_output_registers();
endclass : ${module_instance_name}_rst_safe_random_dout_din_vseq


function ${module_instance_name}_rst_safe_random_dout_din_vseq::new(string name = "");
  super.new(name);
  ${module_instance_name}_rst_safe_config_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_random_dout_din_config_parameters::get_type());
endfunction : new


task ${module_instance_name}_rst_safe_random_dout_din_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    case (config_params.op_select)
      0:       drive_inputs_and_read();
      default: program_output_registers();
    endcase
  end
endtask : main_thread


task ${module_instance_name}_rst_safe_random_dout_din_vseq::drive_inputs_and_read();
  bit [TL_DW-1:0] rd_data;

  // The device must not be driving a pin the testbench is about to drive, or the net resolves
  // to x and the checker reports contention.
  csr_wr(.ptr(ral.direct_oe), .value('0));
  drive_pins(.value(config_params.gpio_i),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(config_params.inter_op_cycles + FILTER_CYCLES + 2));

  csr_rd(.ptr(ral.data_in), .value(rd_data));
endtask : drive_inputs_and_read


task ${module_instance_name}_rst_safe_random_dout_din_vseq::program_output_registers();
  // Release the inputs first, for the same reason the other arm clears the output enables.
  drive_pins(.value('0),
             .drive_en('0),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(config_params.inter_op_cycles));

  // csr_wr rather than csr_update: these registers take effect on the write itself, so a
  // mirror that already holds the value must not suppress the bus transaction.
  if (config_params.reg_write_mask[0]) begin
    csr_wr(.ptr(ral.direct_out), .value(config_params.csr_value));
  end
  if (config_params.reg_write_mask[1]) begin
    csr_wr(.ptr(ral.direct_oe), .value(config_params.csr_value));
  end
  if (config_params.reg_write_mask[2]) begin
    csr_wr(.ptr(ral.masked_out_lower), .value(config_params.csr_value));
  end
  if (config_params.reg_write_mask[3]) begin
    csr_wr(.ptr(ral.masked_oe_lower), .value(config_params.csr_value));
  end
  if (config_params.reg_write_mask[4]) begin
    csr_wr(.ptr(ral.masked_out_upper), .value(config_params.csr_value));
  end
  if (config_params.reg_write_mask[5]) begin
    csr_wr(.ptr(ral.masked_oe_upper), .value(config_params.csr_value));
  end
endtask : program_output_registers
