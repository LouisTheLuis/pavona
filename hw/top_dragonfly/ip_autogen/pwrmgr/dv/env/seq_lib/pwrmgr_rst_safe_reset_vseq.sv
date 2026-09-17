// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the reset test: several rounds, no reset from the framework. The device is
// reset by the stimulus itself, which is the point of the test.
class pwrmgr_rst_safe_reset_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_reset_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[2 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_reset_test_seq_parameters


// Resets asked for by the peripherals, and by a dip on the main power supply.
//
// A request only resets the device if software has enabled it, so each round raises a mixture and
// the device should act on the enabled ones alone. The enable reaches the slow domain only when
// software asks, so each round asks before raising anything. No wakeups are raised here.
class pwrmgr_rst_safe_reset_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_reset_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_reset_round();
endclass : pwrmgr_rst_safe_reset_vseq


function pwrmgr_rst_safe_reset_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_reset_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_reset_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf(
              "Reset round %0d of %0d: requests 0x%0x, enabled 0x%0x, glitch %0b",
              i + 1, test_params.num_trans, config_params.resets, config_params.resets_en,
              config_params.power_glitch), UVM_MEDIUM)
    run_reset_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_reset_vseq::run_reset_round();
  uvm_reg_data_t rd_value;
  bit expect_reset = ((config_params.resets & config_params.resets_en) != '0) ||
                     config_params.power_glitch;

  csr_wr(.ptr(ral.intr_enable.wakeup), .value(config_params.en_intr));
  csr_wr(.ptr(ral.reset_en), .value(config_params.resets_en));
  propagate_to_slow_domain();

  discard_stale_observations();

  // The glitch goes first. Sent after the requests it would cause a second reset behind the
  // first, which is a different scenario and not the one this round is set up to check.
  if (config_params.power_glitch) send_power_glitch(config_params.glitch_width_slow_clks);
  set_reset_requests(config_params.resets);

  if (expect_reset) wait_for_device_active();

  // Nothing asked for a wakeup, so the device recorded no reason and raised no interrupt. The
  // scoreboard holds those expectations; these reads are what it compares against.
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.reset_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  // Take the requests away, or the device would reset again as soon as it came back.
  set_reset_requests('0);
endtask : run_reset_round
