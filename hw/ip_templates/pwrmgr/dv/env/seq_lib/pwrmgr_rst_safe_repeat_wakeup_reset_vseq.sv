// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the lifecycle corruption overlay: many short rounds, with the framework
// applying resets through them.
class pwrmgr_rst_safe_repeat_wakeup_reset_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_repeat_wakeup_reset_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops == 3;}

  constraint num_trans_c {num_trans inside {[4 : 8]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_repeat_wakeup_reset_test_seq_parameters


// Wakeups and resets run with the lifecycle broadcast corrupted underneath them. The device treats
// anything that is not a clean enabled encoding as not enabled, and this sends clean and corrupt
// encodings alike while the device does its ordinary work.
//
// It is an overlay rather than a scenario of its own: the wakeup and the reset are the same ones
// their own sequences perform. The broadcast is held across them rather than pulsed, because the
// device reads it as a level whenever it needs it, so there is no moment to hit.
class pwrmgr_rst_safe_repeat_wakeup_reset_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_repeat_wakeup_reset_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_wakeup_round();
  extern protected task run_reset_round();
endclass : pwrmgr_rst_safe_repeat_wakeup_reset_vseq


function pwrmgr_rst_safe_repeat_wakeup_reset_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_repeat_wakeup_reset_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_repeat_wakeup_reset_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)

    // The broadcast is set before the round and left standing through it.
    `uvm_info(`gfn, $sformatf("Round %0d of %0d with debug_en 0x%0x and dft_en 0x%0x", i + 1,
                              test_params.num_trans, config_params.lc_hw_debug_en,
                              config_params.lc_dft_en), UVM_MEDIUM)
    // The device will not go to low power while the broadcast says debug is enabled, so the wakeup
    // rounds keep that enable clean and corrupt the test enable, and the reset rounds corrupt both.
    if (i % 2 == 0) begin
      set_lifecycle_broadcast(.hw_debug_en(lc_ctrl_pkg::Off), .dft_en(config_params.lc_dft_en));
      run_wakeup_round();
    end else begin
      set_lifecycle_broadcast(.hw_debug_en(config_params.lc_hw_debug_en),
                              .dft_en(config_params.lc_dft_en));
      run_reset_round();
    end
  end
endtask : main_thread


task pwrmgr_rst_safe_repeat_wakeup_reset_vseq::run_wakeup_round();
  uvm_reg_data_t rd_value;

  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  csr_wr(.ptr(ral.intr_enable.wakeup), .value(config_params.en_intr));

  stage_clock_enables();
  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_processor_sleeping(1'b1);
  wait_for_low_power_entry();

  discard_stale_observations();
  set_wakeups(config_params.wakeups);
  wait_for_device_active();

  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  set_wakeups('0);
  set_processor_sleeping(1'b0);
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
endtask : run_wakeup_round


task pwrmgr_rst_safe_repeat_wakeup_reset_vseq::run_reset_round();
  uvm_reg_data_t rd_value;

  csr_wr(.ptr(ral.reset_en), .value(config_params.resets_en));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_reset_requests(config_params.resets);
  wait_for_device_active();

  csr_rd(.ptr(ral.reset_status[0]), .value(rd_value));

  set_reset_requests('0);
endtask : run_reset_round
