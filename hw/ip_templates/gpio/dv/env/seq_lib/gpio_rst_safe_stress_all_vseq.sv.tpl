// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class ${module_instance_name}_rst_safe_stress_all_test_seq_parameters
    extends ${module_instance_name}_rst_safe_test_seq_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_stress_all_test_seq_parameters)

  constraint reset_enable_c {
    reset_testing == DISABLE;
  }

  constraint reset_loops_c {
    num_reset_loops == 1;
  }

  constraint num_trans_c {
    num_trans inside {[1:10]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_stress_all_test_seq_parameters


class ${module_instance_name}_rst_safe_stress_all_config_parameters
    extends cip_rst_safe_stress_all_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_stress_all_config_parameters)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_stress_all_config_parameters


class ${module_instance_name}_rst_safe_stress_all_vseq extends cip_rst_safe_stress_all_vseq #(
    .RAL_T               (${module_instance_name}_reg_block),
    .CFG_T               (${module_instance_name}_env_cfg),
    .COV_T               (${module_instance_name}_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T (${module_instance_name}_rst_safe_virtual_sequencer),
    .TEST_PARAMS_T       (${module_instance_name}_rst_safe_stress_all_test_seq_parameters),
    .CONFIG_PARAMS_T     (${module_instance_name}_rst_safe_stress_all_config_parameters)
  );
  `uvm_object_utils(${module_instance_name}_rst_safe_stress_all_vseq)

  extern function new(string name = "");
  extern virtual function void get_stress_seq_names(ref string seq_names[$]);
  extern virtual function void configure_stress_child(uvm_sequence selected_seq);
endclass : ${module_instance_name}_rst_safe_stress_all_vseq


function ${module_instance_name}_rst_safe_stress_all_vseq::new(string name = "");
  super.new(name);
endfunction : new


function void ${module_instance_name}_rst_safe_stress_all_vseq::get_stress_seq_names(ref string seq_names[$]);
  seq_names = '{
      "${module_instance_name}_rst_safe_smoke_vseq",
      "${module_instance_name}_rst_safe_common_vseq",
      "${module_instance_name}_rst_safe_random_dout_din_vseq",
      "${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq",
      "${module_instance_name}_rst_safe_intr_rand_pgm_vseq",
      "${module_instance_name}_rst_safe_rand_intr_trigger_vseq",
      "${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq",
      "${module_instance_name}_rst_safe_full_random_vseq",
      "${module_instance_name}_rst_safe_intr_with_filter_rand_intr_event_vseq",
      "${module_instance_name}_rst_safe_filter_stress_vseq",
% if num_inp_period_counters > 0:
      "${module_instance_name}_rst_safe_inp_prd_cnt_vseq",
% endif
      // Included so that the strap sample is requested in more than one order relative to the
      // other traffic. The device samples once per reset, so a second child asking for one is
      // a check that the first sample survives.
      "${module_instance_name}_rst_safe_rand_straps_vseq"
  };
endfunction : get_stress_seq_names


function void ${module_instance_name}_rst_safe_stress_all_vseq::configure_stress_child(
    uvm_sequence selected_seq);
  ${module_instance_name}_rand_rst_safe_base_vseq rst_safe_child;
  ${module_instance_name}_rst_safe_common_vseq    common_child;

  if (!$cast(rst_safe_child, selected_seq)) begin
    `uvm_fatal(`gfn, $sformatf("Unsupported reset-safe stress-all child sequence %s",
                               selected_seq.get_type_name()))
  end

  // The wrapper owns reset for the whole run, so no child may drive it.
  rst_safe_child.do_apply_reset        = 1'b0;
  rst_safe_child.reset_ctrl_higher_seq = 1'b1;

  if ($cast(common_child, selected_seq)) begin
    common_child.common_seq_type = "intr_test";
  end
endfunction : configure_stress_child
