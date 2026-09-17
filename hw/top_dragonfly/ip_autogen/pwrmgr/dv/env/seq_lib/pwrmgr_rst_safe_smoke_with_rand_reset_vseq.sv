// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test shape for the reset form of the smoke: the smoke's shape with reset turned on.
class pwrmgr_rst_safe_smoke_with_rand_reset_test_seq_parameters
    extends pwrmgr_rst_safe_smoke_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_smoke_with_rand_reset_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops inside {[2 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_smoke_with_rand_reset_test_seq_parameters


// The smoke flow with the power-on reset enabled, so reset lands in the middle of a transition or a
// wakeup. Nothing about the functional work changes, which is what makes the two comparable: only
// the test shape differs, and the inherited body still owns the reset loop.
class pwrmgr_rst_safe_smoke_with_rand_reset_vseq extends pwrmgr_rst_safe_smoke_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_smoke_with_rand_reset_vseq)

  extern function new(string name = "");
endclass : pwrmgr_rst_safe_smoke_with_rand_reset_vseq


function pwrmgr_rst_safe_smoke_with_rand_reset_vseq::new(string name = "");
  // The smoke's own constructor installs the no-reset shape first. Replacing it here after
  // that call is the whole mechanism: the last override wins, so this sequence gets the reset
  // shape while the plain smoke keeps the other one.
  super.new(name);
  pwrmgr_rst_safe_test_seq_parameters::type_id::set_type_override(
      pwrmgr_rst_safe_smoke_with_rand_reset_test_seq_parameters::get_type());
endfunction : new
