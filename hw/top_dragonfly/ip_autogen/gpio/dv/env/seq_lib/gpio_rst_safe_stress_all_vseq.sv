// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class gpio_rst_safe_stress_all_test_seq_parameters
    extends gpio_rst_safe_test_seq_parameters;
  `uvm_object_utils(gpio_rst_safe_stress_all_test_seq_parameters)

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
endclass : gpio_rst_safe_stress_all_test_seq_parameters


class gpio_rst_safe_stress_all_config_parameters
    extends cip_rst_safe_stress_all_config_parameters;
  `uvm_object_utils(gpio_rst_safe_stress_all_config_parameters)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_stress_all_config_parameters


class gpio_rst_safe_stress_all_vseq extends cip_rst_safe_stress_all_vseq #(
    .RAL_T               (gpio_reg_block),
    .CFG_T               (gpio_env_cfg),
    .COV_T               (gpio_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T (gpio_rst_safe_virtual_sequencer),
    .TEST_PARAMS_T       (gpio_rst_safe_stress_all_test_seq_parameters),
    .CONFIG_PARAMS_T     (gpio_rst_safe_stress_all_config_parameters)
  );
  `uvm_object_utils(gpio_rst_safe_stress_all_vseq)

  extern function new(string name = "");
  extern virtual function void get_stress_seq_names(ref string seq_names[$]);
  extern virtual function void configure_stress_child(uvm_sequence selected_seq);
endclass : gpio_rst_safe_stress_all_vseq


function gpio_rst_safe_stress_all_vseq::new(string name = "");
  super.new(name);
endfunction : new


function void gpio_rst_safe_stress_all_vseq::get_stress_seq_names(ref string seq_names[$]);
  seq_names = '{
      "gpio_rst_safe_smoke_vseq",
      "gpio_rst_safe_common_vseq",
      "gpio_rst_safe_random_dout_din_vseq",
      "gpio_rst_safe_dout_din_regs_random_rw_vseq",
      "gpio_rst_safe_intr_rand_pgm_vseq",
      "gpio_rst_safe_rand_intr_trigger_vseq",
      "gpio_rst_safe_random_long_reg_writes_reg_reads_vseq",
      "gpio_rst_safe_full_random_vseq",
      "gpio_rst_safe_intr_with_filter_rand_intr_event_vseq",
      "gpio_rst_safe_filter_stress_vseq",
      "gpio_rst_safe_inp_prd_cnt_vseq",
      // Included so that the strap sample is requested in more than one order relative to the
      // other traffic. The device samples once per reset, so a second child asking for one is
      // a check that the first sample survives.
      "gpio_rst_safe_rand_straps_vseq"
  };
endfunction : get_stress_seq_names


function void gpio_rst_safe_stress_all_vseq::configure_stress_child(
    uvm_sequence selected_seq);
  gpio_rand_rst_safe_base_vseq rst_safe_child;
  gpio_rst_safe_common_vseq    common_child;

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
