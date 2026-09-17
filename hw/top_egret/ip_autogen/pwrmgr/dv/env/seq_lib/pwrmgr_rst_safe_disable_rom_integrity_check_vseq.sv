// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the rom check gate: a few rounds, each of which resets the device itself, so the
// framework adds none of its own.
class pwrmgr_rst_safe_disable_rom_integrity_check_test_seq_parameters
    extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_disable_rom_integrity_check_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[2 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_disable_rom_integrity_check_test_seq_parameters


// What the rom reports after a reset decides whether the device runs at all, and the lifecycle
// broadcast can overrule it.
//
// The device waits for every rom to report finished and good; one that never finishes, or finishes
// badly, leaves it short of active indefinitely. The ways out are the rom changing its answer, or
// debug and test being enabled in the broadcast. This drives both.
//
// One rom is answered for and the rest report a finished, good check, so what is under test is the
// gate rather than the device waiting on a peer that was never asked.
class pwrmgr_rst_safe_disable_rom_integrity_check_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_disable_rom_integrity_check_vseq)

  // Which rom is answered for, and whether the way out of a bad result is the rom correcting
  // itself or the lifecycle broadcast overruling it.
  rand int unsigned rom_index;
  rand bit          release_by_good;

  constraint rom_index_c {rom_index < pwrmgr_reg_pkg::NumRomInputs;}

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_rom_check_round();
endclass : pwrmgr_rst_safe_disable_rom_integrity_check_vseq


function pwrmgr_rst_safe_disable_rom_integrity_check_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_disable_rom_integrity_check_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_disable_rom_integrity_check_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(this)
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    run_rom_check_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_disable_rom_integrity_check_vseq::run_rom_check_round();
  uvm_reg_data_t rd_value;

  // The broadcast says debug and test are off, so the check cannot be skipped and the rom's answer
  // is what decides. This is set before the reset because the device reads it on the way up.
  set_lifecycle_broadcast(.hw_debug_en(lc_ctrl_pkg::Off), .dft_en(lc_ctrl_pkg::Off));

  // Neither finished nor good. The device is expected to hold short of running on the first of
  // those, and the second is what it meets once the first is answered.
  set_rom_response(.index(rom_index), .done(MuBi4False), .good(MuBi4False));

  csr_wr(.ptr(ral.reset_en), .value(config_params.resets_en));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_reset_requests(config_params.resets);

  // Coming out of the reset the device asks the rom, and the rom has not finished. Saying it has
  // finished leaves the bad result standing, which is the state the way out is needed for.
  wait_for_low_power_entry_started();
  set_rom_response(.index(rom_index), .done(MuBi4True), .good(MuBi4False));

  if (release_by_good) begin
    `uvm_info(`gfn, "Letting the rom correct its own result", UVM_MEDIUM)
    set_rom_response(.index(rom_index), .done(MuBi4True), .good(MuBi4True));
  end else begin
    // Debug and test enabled is what tells the device the check may be skipped, so the bad result
    // stands and the device runs anyway. That is the behavior this test is named for.
    `uvm_info(`gfn, "Overruling the rom result through the lifecycle broadcast", UVM_MEDIUM)
    set_lifecycle_broadcast(.hw_debug_en(lc_ctrl_pkg::On), .dft_en(lc_ctrl_pkg::On));
  end

  wait_for_device_active();

  set_reset_requests('0);
  csr_rd(.ptr(ral.reset_status[0]), .value(rd_value));
endtask : run_rom_check_round
