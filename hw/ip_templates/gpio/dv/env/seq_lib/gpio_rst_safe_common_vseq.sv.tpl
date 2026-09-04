// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe wrapper for the common CSR tests. The wrapper runs inside main_thread(), which is
// what lets the reset-safe base terminate it as a unit when reset is asserted.
class ${module_instance_name}_rst_safe_common_test_seq_parameters
    extends ${module_instance_name}_rst_safe_test_seq_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_common_test_seq_parameters)

  constraint reset_enable_c {
    reset_testing == ENABLE;
  }

  constraint reset_loops_c {
    num_reset_loops == 3;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_common_test_seq_parameters


class ${module_instance_name}_rst_safe_common_config_parameters
    extends ${module_instance_name}_rst_safe_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_common_config_parameters)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_common_config_parameters


class ${module_instance_name}_rst_safe_common_vseq
    extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_common_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
endclass : ${module_instance_name}_rst_safe_common_vseq


function ${module_instance_name}_rst_safe_common_vseq::new(string name = "");
  super.new(name);
  ${module_instance_name}_rst_safe_test_seq_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_common_test_seq_parameters::get_type());
  ${module_instance_name}_rst_safe_config_parameters::type_id::set_type_override(
      ${module_instance_name}_rst_safe_common_config_parameters::get_type());
endfunction : new


task ${module_instance_name}_rst_safe_common_vseq::main_thread();
  delay_seq del_seq;

  // The interrupt part of the common wrapper writes INTR_TEST and expects INTR_STATE to hold
  // exactly what it wrote. That only holds if nothing else is raising interrupts, and this
  // sequence runs under the stress wrapper, which turns dut_init() off and leaves whatever
  // interrupt sources the previous child enabled still enabled. The pins are static by then,
  // but a level source asserts on a standing value and an edge source on the next change.
  csr_wr(.ptr(ral.intr_ctrl_en_rising),  .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_falling), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_lvllow),  .value('0));
  csr_wr(.ptr(ral.intr_state), .value('1));

  run_common_vseq_wrapper(.num_times(1));

  // Keep main_thread() running after the wrapper returns, so a reset trigger still has a
  // window to land in rather than finding the workload already over.
  del_seq = delay_seq::type_id::create("del_seq:main_thread");
  `DV_CHECK_RANDOMIZE_FATAL(del_seq)
  del_seq.start(p_sequencer.delay_sequencer_h);
endtask : main_thread
