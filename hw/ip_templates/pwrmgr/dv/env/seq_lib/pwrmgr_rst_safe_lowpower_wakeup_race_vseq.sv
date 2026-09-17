// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the racing test: several rounds, no power-on reset.
class pwrmgr_rst_safe_lowpower_wakeup_race_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_lowpower_wakeup_race_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}
  constraint reset_loops_c {num_reset_loops == 1;}
  constraint num_trans_c {num_trans inside {[2 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_lowpower_wakeup_race_test_seq_parameters


// A wakeup arriving at the same moment the device is told to go to sleep, placed within a few
// cycles so the device decides between them. Afterwards every source is raised, which the device is
// still recording: capture runs until software stops it, so a wakeup raised after the device is
// running again is recorded too.
class pwrmgr_rst_safe_lowpower_wakeup_race_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_lowpower_wakeup_race_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_race_round();
endclass : pwrmgr_rst_safe_lowpower_wakeup_race_vseq


function pwrmgr_rst_safe_lowpower_wakeup_race_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_lowpower_wakeup_race_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_lowpower_wakeup_race_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `uvm_info(`gfn, $sformatf(
              "Race round %0d of %0d: sleep at %0d, wakeup 0x%0x at %0d",
              i + 1, test_params.num_trans, config_params.cycles_before_transition,
              config_params.wakeups, config_params.cycles_before_early_wakeup), UVM_MEDIUM)
    run_race_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_lowpower_wakeup_race_vseq::run_race_round();
  uvm_reg_data_t rd_value;

  csr_wr(.ptr(ral.wakeup_en[0]), .value(config_params.wakeups_en));
  csr_wr(.ptr(ral.intr_enable.wakeup), .value(config_params.en_intr));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(config_params.disable_wakeup_capture));

  ral.control.low_power_hint.set(1'b1);
  ral.control.main_pd_n.set(config_params.main_pd_n);
  csr_wr(.ptr(ral.control), .value(ral.control.get()));
  propagate_to_slow_domain();

  discard_stale_observations();

  // Both inputs are placed by their own driver, on the clock each belongs to, so the two land
  // within a few cycles of one another however the device happens to be running.
  fork
    set_processor_sleeping_after(1'b1, config_params.cycles_before_transition);
    set_wakeups_after(config_params.wakeups, config_params.cycles_before_early_wakeup);
  join

  wait_for_device_active();

  // Every source, now that the device is running again. It is still recording, so these are
  // recorded as well, and the enabled ones are what the checker expects to find.
  set_wakeups('1);
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.wake_status[0]), .value(rd_value));

  set_wakeups('0);
  set_processor_sleeping(1'b0);
  csr_wr(.ptr(ral.intr_state), .value(1'b1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b1));
  csr_wr(.ptr(ral.wake_info), .value('1));
  csr_wr(.ptr(ral.wake_info_capture_dis), .value(1'b0));
endtask : run_race_round
