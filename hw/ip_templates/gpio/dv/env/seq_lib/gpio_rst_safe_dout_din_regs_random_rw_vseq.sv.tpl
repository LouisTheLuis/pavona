// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Each operation either drives the inputs and reads DATA_IN, or writes one of the data
// registers, or reads one of them. One access per operation, so the register traffic is spread
// through the epoch rather than gathered into bursts.
class ${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters
    extends ${module_instance_name}_rst_safe_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters)

  // Which of the data registers the write or read arm uses.
  rand int unsigned reg_select;

  constraint op_select_c {
    op_select inside {[0:2]};
  }

  constraint reg_select_c {
    reg_select inside {[0:6]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters


class ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq
    extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_inputs_and_read();
  extern protected task write_one_data_register();
  extern protected task read_one_data_register();
endclass : ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq


function ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq::new(string name = "");
  super.new(name);
  ${module_instance_name}_rst_safe_config_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters::get_type());
endfunction : new


task ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    case (config_params.op_select)
      0:       drive_inputs_and_read();
      1:       write_one_data_register();
      default: read_one_data_register();
    endcase
  end
endtask : main_thread


task ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq::drive_inputs_and_read();
  bit [TL_DW-1:0] rd_data;

  // The device stops driving first, so the pins carry what the testbench puts on them.
  csr_wr(.ptr(ral.direct_oe), .value('0));
  drive_pins(.value(config_params.gpio_i),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(config_params.inter_op_cycles + FILTER_CYCLES + 2));

  csr_rd(.ptr(ral.data_in), .value(rd_data));
endtask : drive_inputs_and_read


task ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq::write_one_data_register();
  ${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters params;
  `downcast(params, config_params)

  // The write can enable the device's output drivers, so the testbench lets go of the pins
  // first and leaves them to the weak pulls.
  drive_pins(.value('0),
             .drive_en('0),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(FILTER_CYCLES + 1));

  case (params.reg_select)
    // DATA_IN is written by hardware. Writing it from software should change nothing, which
    // is what the scoreboard's continuous comparison of DATA_IN is checking here.
    0:       csr_wr(.ptr(ral.data_in),          .value(params.csr_value));
    1:       csr_wr(.ptr(ral.direct_out),       .value(params.csr_value));
    2:       csr_wr(.ptr(ral.direct_oe),        .value(params.csr_value));
    3:       csr_wr(.ptr(ral.masked_out_lower), .value(params.csr_value));
    4:       csr_wr(.ptr(ral.masked_oe_lower),  .value(params.csr_value));
    5:       csr_wr(.ptr(ral.masked_out_upper), .value(params.csr_value));
    default: csr_wr(.ptr(ral.masked_oe_upper),  .value(params.csr_value));
  endcase
endtask : write_one_data_register


task ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq::read_one_data_register();
  ${module_instance_name}_rst_safe_dout_din_regs_random_rw_config_parameters params;
  bit [TL_DW-1:0] rd_data;
  `downcast(params, config_params)

  case (params.reg_select)
    0:       csr_rd(.ptr(ral.data_in),          .value(rd_data));
    1:       csr_rd(.ptr(ral.direct_out),       .value(rd_data));
    2:       csr_rd(.ptr(ral.direct_oe),        .value(rd_data));
    3:       csr_rd(.ptr(ral.masked_out_lower), .value(rd_data));
    4:       csr_rd(.ptr(ral.masked_oe_lower),  .value(rd_data));
    5:       csr_rd(.ptr(ral.masked_out_upper), .value(rd_data));
    default: csr_rd(.ptr(ral.masked_oe_upper),  .value(rd_data));
  endcase
endtask : read_one_data_register
