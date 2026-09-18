// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the rom blocker sweep: several rounds on one device, each of which resets it
// itself, so the framework adds none of its own.
class pwrmgr_rst_safe_rom_blockers_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_rom_blockers_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}

  constraint reset_loops_c {num_reset_loops == 1;}

  constraint num_trans_c {num_trans inside {[6 : 10]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_rom_blockers_test_seq_parameters


// One answer per rom, drawn independently, together with the lifecycle broadcast. Drawn from the
// object's own seed so an unrelated edit does not move which combination a given seed drives.
class pwrmgr_rst_safe_rom_answers extends uvm_object;

  rand mubi4_t done[];
  rand mubi4_t good[];
  rand bit [lc_ctrl_pkg::TxWidth-1:0] hw_debug_en;
  rand bit [lc_ctrl_pkg::TxWidth-1:0] dft_en;

  constraint size_c {
    done.size() == pwrmgr_reg_pkg::NumRomInputs;
    good.size() == pwrmgr_reg_pkg::NumRomInputs;
  }

  // The device reads these as multi-bit values, so the two defined encodings have to appear far
  // more often than the rest, which it must treat as not-true.
  constraint answers_c {
    foreach (done[i]) done[i] dist {MuBi4True :/ 4, MuBi4False :/ 4, [0 : 15] :/ 1};
    foreach (good[i]) good[i] dist {MuBi4True :/ 4, MuBi4False :/ 4, [0 : 15] :/ 1};
  }

  constraint lifecycle_c {
    hw_debug_en dist {lc_ctrl_pkg::On :/ 2, lc_ctrl_pkg::Off :/ 2, [0 : 15] :/ 1};
    dft_en dist {lc_ctrl_pkg::On :/ 2, lc_ctrl_pkg::Off :/ 2, [0 : 15] :/ 1};
  }

  `uvm_object_utils(pwrmgr_rst_safe_rom_answers)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_rom_answers


// Drives every rom input independently, rather than one at a time.
//
// The device holds short of active until every rom reports finished and good, and the lifecycle
// broadcast can overrule that. The sequence testing the gate blocks one rom and holds the others
// passing, so on a top with several rom inputs no run ever has two blocking at once and the
// combinations that say the gate is an and rather than a first-match are never driven.
//
// This drives all of them from one draw. Each round ends by letting every rom pass and resetting,
// which is what takes the device out of a state it cannot otherwise leave.
class pwrmgr_rst_safe_rom_blockers_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_rom_blockers_vseq)

  protected pwrmgr_rst_safe_rom_answers answers;

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_one_combination();
  extern protected task release_every_rom();
endclass : pwrmgr_rst_safe_rom_blockers_vseq


function pwrmgr_rst_safe_rom_blockers_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_rom_blockers_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_rom_blockers_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock.
  // Under the stress wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  answers = pwrmgr_rst_safe_rom_answers::type_id::create("answers");

  for (int unsigned round = 0; round < test_params.num_trans; round++) begin
    `DV_CHECK_RANDOMIZE_FATAL(answers)
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    drive_one_combination();
  end
endtask : main_thread


task pwrmgr_rst_safe_rom_blockers_vseq::drive_one_combination();
  `uvm_info(`gfn, $sformatf("Rom answers done=%p good=%p, debug 0x%0x, dft 0x%0x", answers.done,
                            answers.good, answers.hw_debug_en, answers.dft_en), UVM_MEDIUM)

  // Both are placed before the reset, because the device reads them on the way up: the broadcast
  // decides whether a failing rom holds it at all, and the rom answers are what it asks for.
  set_lifecycle_broadcast(.hw_debug_en(answers.hw_debug_en), .dft_en(answers.dft_en));
  set_all_rom_responses(.done(answers.done), .good(answers.good));

  csr_wr(.ptr(ral.reset_en), .value(config_params.resets_en));
  propagate_to_slow_domain();

  discard_stale_observations();
  set_reset_requests(config_params.resets);

  // The device reads the rom answers on its way back up, so the combination has to still be in
  // place when it gets there, or what is recorded is the release rather than the draw.
  wait_for_fast_state(pwrmgr_pkg::FastPwrStateRomCheckDone);

  // Whatever the draw was, the device is let go before the round ends, so a combination that holds
  // it short of running does not hold the next round as well.
  release_every_rom();
  wait_for_device_active();

  set_reset_requests('0);
endtask : drive_one_combination


task pwrmgr_rst_safe_rom_blockers_vseq::release_every_rom();
  mubi4_t passing[];

  passing = new[pwrmgr_reg_pkg::NumRomInputs];
  foreach (passing[i]) passing[i] = MuBi4True;
  set_all_rom_responses(.done(passing), .good(passing));
  set_lifecycle_broadcast(.hw_debug_en(lc_ctrl_pkg::Off), .dft_en(lc_ctrl_pkg::Off));
endtask : release_every_rom
