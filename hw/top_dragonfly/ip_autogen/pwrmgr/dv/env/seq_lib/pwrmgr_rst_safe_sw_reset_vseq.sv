// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the software reset test: many short rounds, no power-on reset.
class pwrmgr_rst_safe_sw_reset_test_seq_parameters extends pwrmgr_rst_safe_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_sw_reset_test_seq_parameters)

  constraint reset_enable_c {reset_testing == DISABLE;}
  constraint reset_loops_c {num_reset_loops == 1;}
  constraint num_trans_c {num_trans inside {[8 : 16]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_sw_reset_test_seq_parameters


// Software reset requests, most of which are not requests at all. rstmgr forwards a multi-bit value
// and only one encoding asks for a reset, so the encodings that do nothing are as much the subject
// as the one that does.
class pwrmgr_rst_safe_sw_reset_vseq extends pwrmgr_rand_rst_safe_base_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_sw_reset_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_sw_reset_round();
endclass : pwrmgr_rst_safe_sw_reset_vseq


function pwrmgr_rst_safe_sw_reset_vseq::new(string name = "");
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_sw_reset_test_seq_parameters::get_type());
endfunction : new


task pwrmgr_rst_safe_sw_reset_vseq::main_thread();
  // The registers live in the fast domain and return only once the device has asked for its clock,
  // so issuing before then leaves the access queued on a sequencer still in reset. Under the stress
  // wrapper the device is already up and this stands down.
  wait_for_device_active_at_start();

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    run_sw_reset_round();
  end
endtask : main_thread


task pwrmgr_rst_safe_sw_reset_vseq::run_sw_reset_round();
  uvm_reg_data_t rd_value;
  bit [MUBI4W-1:0] request    = config_params.sw_rst_req_raw;
  bit            expect_reset = (request == MuBi4True);

  csr_wr(.ptr(ral.intr_enable.wakeup), .value(config_params.en_intr));

  `uvm_info(`gfn, $sformatf("Software reset request 0x%0x, %0sexpecting a reset",
                            request, expect_reset ? "" : "not "), UVM_MEDIUM)

  discard_stale_observations();
  set_sw_reset_request(request);

  if (expect_reset) begin
    // The device goes away and comes back. Waiting for it to say the processor may run again is
    // what marks the end of the reset, and the boundary the checker compares at.
    wait_for_device_active();
  end

  // Nothing asked for a wakeup, so the device should have recorded none and raised no
  // interrupt. The scoreboard holds those expectations; these reads are what it compares.
  csr_rd(.ptr(ral.wake_info.reasons), .value(rd_value));
  csr_rd(.ptr(ral.reset_status[0]), .value(rd_value));
  csr_rd(.ptr(ral.intr_state), .value(rd_value));

  // Put the request back to its idle encoding so the next round starts from nothing.
  set_sw_reset_request(MuBi4False);
endtask : run_sw_reset_round
