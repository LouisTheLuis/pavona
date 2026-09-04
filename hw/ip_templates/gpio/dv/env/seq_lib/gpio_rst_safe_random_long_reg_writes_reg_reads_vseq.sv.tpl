// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Each operation either drives the inputs, or runs a long burst of writes to randomly chosen
// registers, or runs a long burst of reads. The bursts are what the sequence is for: back to
// back register traffic with no pin activity between the accesses.
class ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters
    extends ${module_instance_name}_rst_safe_config_parameters;
  `uvm_object_utils(
      ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters)

  // Accesses in one burst.
  rand int unsigned num_reg_ops;

  // Which register the next access in a burst uses.
  rand int unsigned wr_reg_select;
  rand int unsigned rd_reg_select;

  constraint op_select_c {
    op_select inside {[0:2]};
  }

  constraint num_reg_ops_c {
    num_reg_ops inside {[25:50]};
  }

  constraint wr_reg_select_c {
    wr_reg_select inside {[0:13]};
  }

  // DATA_IN and INTR_STATE are read five times as often as the rest, so most of the traffic
  // is on the two registers hardware can change underneath the access.
  constraint rd_reg_select_c {
    rd_reg_select dist {
      0        :/ 5,
      9        :/ 5,
      [1:8]    :/ 1,
      [10:14]  :/ 1
    };
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters


class ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq
    extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_inputs();
  extern protected task long_register_writes();
  extern protected task long_register_reads();
  extern protected task undrive_inputs();
endclass : ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq


function ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::new(
    string name = "");
  super.new(name);
  ${module_instance_name}_rst_safe_config_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters::
          get_type());
endfunction : new


task ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    case (config_params.op_select)
      0:       drive_inputs();
      1:       long_register_writes();
      default: long_register_reads();
    endcase
  end
endtask : main_thread


task ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::drive_inputs();
  // The device stops driving first, so the pins carry what the testbench puts on them rather
  // than the result of two drivers fighting over the net.
  csr_wr(.ptr(ral.direct_oe), .value('0));
  drive_pins(.value(config_params.gpio_i),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(config_params.inter_op_cycles + FILTER_CYCLES + 2));
endtask : drive_inputs


task ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::undrive_inputs();
  // The write burst can enable the device's own output drivers, so the testbench lets go of
  // the pins and leaves them to the weak pulls first.
  drive_pins(.value('0),
             .drive_en('0),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(FILTER_CYCLES + 1));
endtask : undrive_inputs


task ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::
    long_register_writes();
  ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters outer;
  ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters op;
  `downcast(outer, config_params)

  op = ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters::
      type_id::create("op");

  undrive_inputs();

  for (int unsigned i = 0; i < outer.num_reg_ops; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(op)
    case (op.wr_reg_select)
      0:  csr_wr(.ptr(ral.data_in),              .value(op.csr_value));
      1:  csr_wr(.ptr(ral.direct_out),           .value(op.csr_value));
      2:  csr_wr(.ptr(ral.masked_out_lower),     .value(op.csr_value));
      3:  csr_wr(.ptr(ral.masked_out_upper),     .value(op.csr_value));
      4:  csr_wr(.ptr(ral.direct_oe),            .value(op.csr_value));
      5:  csr_wr(.ptr(ral.masked_oe_lower),      .value(op.csr_value));
      6:  csr_wr(.ptr(ral.masked_oe_upper),      .value(op.csr_value));
      7:  csr_wr(.ptr(ral.intr_enable),          .value(op.csr_value));
      8:  csr_wr(.ptr(ral.intr_test),            .value(op.csr_value));
      9:  csr_wr(.ptr(ral.intr_state),           .value(op.csr_value));
      10: csr_wr(.ptr(ral.intr_ctrl_en_falling), .value(op.csr_value));
      11: csr_wr(.ptr(ral.intr_ctrl_en_rising),  .value(op.csr_value));
      12: csr_wr(.ptr(ral.intr_ctrl_en_lvllow),  .value(op.csr_value));
      default: csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value(op.csr_value));
    endcase
  end
endtask : long_register_writes


task ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq::
    long_register_reads();
  ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters outer;
  ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters op;
  `downcast(outer, config_params)

  op = ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_config_parameters::
      type_id::create("op");

  for (int unsigned i = 0; i < outer.num_reg_ops; i++) begin
    bit [TL_DW-1:0] rd_data;

    `DV_CHECK_RANDOMIZE_FATAL(op)
    case (op.rd_reg_select)
      0:  csr_rd(.ptr(ral.data_in),              .value(rd_data));
      1:  csr_rd(.ptr(ral.direct_out),           .value(rd_data));
      2:  csr_rd(.ptr(ral.masked_out_lower),     .value(rd_data));
      3:  csr_rd(.ptr(ral.masked_out_upper),     .value(rd_data));
      4:  csr_rd(.ptr(ral.direct_oe),            .value(rd_data));
      5:  csr_rd(.ptr(ral.masked_oe_lower),      .value(rd_data));
      6:  csr_rd(.ptr(ral.masked_oe_upper),      .value(rd_data));
      7:  csr_rd(.ptr(ral.intr_enable),          .value(rd_data));
      8:  csr_rd(.ptr(ral.intr_test),            .value(rd_data));
      9:  csr_rd(.ptr(ral.intr_state),           .value(rd_data));
      10: csr_rd(.ptr(ral.intr_ctrl_en_falling), .value(rd_data));
      11: csr_rd(.ptr(ral.intr_ctrl_en_rising),  .value(rd_data));
      12: csr_rd(.ptr(ral.intr_ctrl_en_lvllow),  .value(rd_data));
      13: csr_rd(.ptr(ral.intr_ctrl_en_lvlhigh), .value(rd_data));
      default: csr_rd(.ptr(ral.ctrl_en_input_filter), .value(rd_data));
    endcase
  end
endtask : long_register_reads
