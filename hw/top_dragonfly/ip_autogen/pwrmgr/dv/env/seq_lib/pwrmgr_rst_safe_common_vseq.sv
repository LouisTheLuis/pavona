// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe wrapper for the common register and security tests. The wrapper runs inside
// main_thread(), which is what lets the reset-safe base terminate it as a unit at reset.
class pwrmgr_rst_safe_common_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_common_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops == 3;}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_common_test_seq_parameters


class pwrmgr_rst_safe_common_config_parameters extends pwrmgr_rst_safe_config_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_common_config_parameters)

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_common_config_parameters


class pwrmgr_rst_safe_common_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_common_vseq)

  extern function new(string name = "");
  extern virtual task pre_start();
  extern virtual task main_thread();
  extern virtual function void sec_cm_fi_ctrl_svas(sec_cm_base_if_proxy if_proxy, bit enable);
endclass : pwrmgr_rst_safe_common_vseq


function pwrmgr_rst_safe_common_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_common_test_seq_parameters::get_type());
  pwrmgr_rst_safe_config_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_common_config_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_common_vseq::pre_start();
  csr_excl_item csr_excl;

  // The register model is not in place until the base has run, so the exclusion is taken after.
  super.pre_start();
  csr_excl = ral.get_excl_item();

  // A power-on reset in this testbench takes main power away, which is what a glitch is, so the
  // device records a fault for it. The common register tests have no way to tell the two apart
  // and would read a fault status they did not cause.
  csr_excl.add_excl("pwrmgr_reg_block.fault_status", CsrExclCheck);
endtask : pre_start


task pwrmgr_rst_safe_common_vseq::main_thread();
  delay_seq del_seq;

  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  // The interrupt part of the wrapper expects the state register to hold exactly what it wrote, and
  // the device raises the wakeup interrupt itself whenever an enabled source is asserted.
  set_wakeups('0);
  csr_wr(.ptr(ral.wakeup_en[0]), .value('0));
  csr_wr(.ptr(ral.intr_state), .value('1));

  run_common_vseq_wrapper(.num_times(1));

  // Hand back a device with no interrupt standing. The next sequence waits for the device to raise
  // one, which it announces only when it changes, so one already high never changes again. What
  // that sequence sees is what is left behind, so clearing before this one runs is not enough.
  csr_wr(.ptr(ral.intr_state), .value('1));

  // Keep this thread running after the wrapper returns, so a reset still has a window to land
  // in rather than finding the workload already over.
  del_seq = delay_seq::type_id::create("del_seq");
  `DV_CHECK_RANDOMIZE_FATAL(del_seq)
  del_seq.start(p_sequencer.delay_sequencer_h);
endtask : main_thread


// Corrupting the state machine leaves the device somewhere an assertion about the rom check does
// not expect to find it, so that assertion is stood down for the injection and put back after.
function void pwrmgr_rst_safe_common_vseq::sec_cm_fi_ctrl_svas(sec_cm_base_if_proxy if_proxy,
                                                               bit enable);
  if (!uvm_re_match("*.u_fast_fsm.u_state_regs*", if_proxy.path)) begin
    if (!enable) $assertoff(0, "tb.dut.pwrmgr_sec_cm_checker_assert.RomBlockActiveState_A");
    else         $asserton(0, "tb.dut.pwrmgr_sec_cm_checker_assert.RomBlockActiveState_A");
  end
endfunction : sec_cm_fi_ctrl_svas
