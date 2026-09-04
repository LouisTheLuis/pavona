// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Randomly either drives the inputs and reads them back, or programs the interrupt control
// registers, and reads INTR_STATE after either.
class gpio_rst_safe_intr_rand_pgm_config_parameters
    extends gpio_rst_safe_config_parameters;
  `uvm_object_utils(gpio_rst_safe_intr_rand_pgm_config_parameters)

  // The value written to whichever interrupt control registers this operation selects.
  rand bit [TL_DW-1:0] intr_reg_value;

  constraint op_select_c {
    op_select inside {[0:1]};
  }

  constraint reg_write_mask_c {
    reg_write_mask != '0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_intr_rand_pgm_config_parameters


class gpio_rst_safe_intr_rand_pgm_vseq
    extends gpio_rand_rst_safe_base_vseq;
  `uvm_object_utils(gpio_rst_safe_intr_rand_pgm_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_inputs_and_read();
  extern protected task program_interrupt_registers();
endclass : gpio_rst_safe_intr_rand_pgm_vseq


function gpio_rst_safe_intr_rand_pgm_vseq::new(string name = "");
  super.new(name);
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_intr_rand_pgm_config_parameters::get_type());
endfunction : new


task gpio_rst_safe_intr_rand_pgm_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    bit [TL_DW-1:0] rd_data;

    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    case (config_params.op_select)
      0:       drive_inputs_and_read();
      default: program_interrupt_registers();
    endcase

    // The legacy sequence reads INTR_STATE after either arm, which is what gives the
    // interrupt model something to be checked against on the operations that only program
    // registers.
    csr_rd(.ptr(ral.intr_state), .value(rd_data));
  end
endtask : main_thread


task gpio_rst_safe_intr_rand_pgm_vseq::drive_inputs_and_read();
  bit [TL_DW-1:0] rd_data;

  csr_wr(.ptr(ral.direct_oe), .value('0));
  drive_pins(.value(config_params.gpio_i),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(config_params.inter_op_cycles + FILTER_CYCLES + 2));

  csr_rd(.ptr(ral.data_in), .value(rd_data));
endtask : drive_inputs_and_read


task gpio_rst_safe_intr_rand_pgm_vseq::program_interrupt_registers();
  gpio_rst_safe_intr_rand_pgm_config_parameters params;
  `downcast(params, config_params)

  if (config_params.reg_write_mask[0]) begin
    csr_wr(.ptr(ral.intr_enable), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[1]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_falling), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[2]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_rising), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[3]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvllow), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[4]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[5]) begin
    // W1C, so this clears whichever bits the value selects.
    csr_wr(.ptr(ral.intr_state), .value(params.intr_reg_value));
  end
endtask : program_interrupt_registers
