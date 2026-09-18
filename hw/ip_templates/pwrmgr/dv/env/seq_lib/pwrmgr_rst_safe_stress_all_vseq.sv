// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Runs the ported sequences one after another on a device that is never reset between them.
//
// Four are left out. The two that corrupt the state machine wedge the device where only a reset
// frees it, so whatever ran next would find a device answering nothing. The random reset smoke and
// the rom integrity check each own a reset, and reset here belongs to this wrapper.
class pwrmgr_rst_safe_stress_all_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_stress_all_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[3 : 8]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_stress_all_test_seq_parameters


class pwrmgr_rst_safe_stress_all_config_parameters
    extends cip_rst_safe_stress_all_config_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_stress_all_config_parameters)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_stress_all_config_parameters


class pwrmgr_rst_safe_stress_all_vseq extends cip_rst_safe_stress_all_vseq #(
    .RAL_T               (pwrmgr_reg_block),
    .CFG_T               (pwrmgr_env_cfg),
    .COV_T               (pwrmgr_env_cov),
    .VIRTUAL_SEQUENCER_T (pwrmgr_rst_safe_virtual_sequencer),
    .TEST_PARAMS_T       (pwrmgr_rst_safe_stress_all_test_seq_parameters),
    .CONFIG_PARAMS_T     (pwrmgr_rst_safe_stress_all_config_parameters)
  );

  `uvm_object_utils(pwrmgr_rst_safe_stress_all_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern virtual function void get_stress_seq_names(ref string seq_names[$]);
  extern virtual function void configure_stress_child(uvm_sequence selected_seq);
endclass : pwrmgr_rst_safe_stress_all_vseq


function pwrmgr_rst_safe_stress_all_vseq::new(string name = "");
  super.new(name);
endfunction : new


// The wait for the device to come up belongs here rather than in each child: it is answered by an
// announcement the device makes only when the processor is let to run, so only the first sequence
// after a reset could hear it.
task pwrmgr_rst_safe_stress_all_vseq::main_thread();
  pwrmgr_active_item item;

  `uvm_info(`gfn, "Waiting for the device to report the processor may run", UVM_MEDIUM)
  `DV_SPINWAIT(forever begin
                 p_sequencer.active_fifo.get(item);
                 if (item.fetch_en == lc_ctrl_pkg::On) break;
               end,
               "timed out waiting for the device to become active",
               // Widened before multiplying, as the base sequence does: the period is an int,
               // and on a top whose always-on clock is far below its bus clock the product
               // leaves thirty two bits and wraps to a fraction of the wait that was asked for.
               int'((longint'(FastObsTimeoutAonCycles) *
                     cfg.slow_clk_rst_vif.clk_period_ps) / 1000))
  `uvm_info(`gfn, "The device is active", UVM_MEDIUM)

  super.main_thread();

  // The children are finished and a reset may still be owed. Ending here would leave it nothing to
  // land in, which the framework reports as the reset thread outliving its work, so the thread
  // stays alive while one is coming and the framework kills it on arrival. The same condition the
  // framework forks on is used, so the two agree that one is coming.
  if (test_params.reset_testing == dv_test_seq_parameters::ENABLE &&
      test_params.num_reset_loops != 0) begin
    forever begin
      delay_seq tail_seq = delay_seq::type_id::create("stress_all_tail");
      `DV_CHECK_RANDOMIZE_FATAL(tail_seq)
      tail_seq.start(p_sequencer.delay_sequencer_h);
    end
  end
endtask : main_thread


function void pwrmgr_rst_safe_stress_all_vseq::get_stress_seq_names(ref string seq_names[$]);
  seq_names.push_back("pwrmgr_rst_safe_smoke_vseq");
  seq_names.push_back("pwrmgr_rst_safe_wakeup_vseq");
  seq_names.push_back("pwrmgr_rst_safe_aborted_low_power_vseq");
  seq_names.push_back("pwrmgr_rst_safe_lowpower_wakeup_race_vseq");
  seq_names.push_back("pwrmgr_rst_safe_sec_cm_ctrl_config_regwen_vseq");
  seq_names.push_back("pwrmgr_rst_safe_reset_vseq");
  seq_names.push_back("pwrmgr_rst_safe_sw_reset_vseq");
  seq_names.push_back("pwrmgr_rst_safe_repeat_wakeup_reset_vseq");
  seq_names.push_back("pwrmgr_rst_safe_glitch_vseq");
  seq_names.push_back("pwrmgr_rst_safe_global_esc_vseq");
  seq_names.push_back("pwrmgr_rst_safe_escalation_timeout_vseq");
  seq_names.push_back("pwrmgr_rst_safe_esc_clk_rst_malfunc_vseq");
  seq_names.push_back("pwrmgr_rst_safe_common_vseq");
endfunction : get_stress_seq_names


function void pwrmgr_rst_safe_stress_all_vseq::configure_stress_child(uvm_sequence selected_seq);
  pwrmgr_rand_rst_safe_base_vseq rst_safe_child;
  pwrmgr_rst_safe_common_vseq    common_child;

  if (!$cast(rst_safe_child, selected_seq)) begin
    `uvm_fatal(`gfn, $sformatf("Unsupported reset-safe stress-all child sequence %s",
                               selected_seq.get_type_name()))
  end

  // Reset belongs to this wrapper. A child brings its own workload and nothing else: the second
  // flag is what stands its reset thread down, so a child that asks for reset testing on its own
  // still does not take one here.
  rst_safe_child.do_apply_reset        = 1'b0;
  rst_safe_child.reset_ctrl_higher_seq = 1'b1;

  // The common wrapper picks what it runs from a string rather than from its type. The interrupt
  // test is the one this sequence prepares for, clearing the wakeup sources and the interrupt
  // state so nothing the device raised itself is mistaken for what the test wrote.
  if ($cast(common_child, selected_seq)) common_child.common_seq_type = "intr_test";
endfunction : configure_stress_child
