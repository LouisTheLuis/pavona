// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The same children as the stress-all wrapper, with the framework taking a reset while one of them
// is part way through its work. What this adds over the wrapper it extends is the reset landing
// somewhere a sequence did not choose, which is the property the whole reset-safe path exists for.
class pwrmgr_rst_safe_stress_all_with_rand_reset_test_seq_parameters
    extends pwrmgr_rst_safe_stress_all_test_seq_parameters;

  `uvm_object_utils(pwrmgr_rst_safe_stress_all_with_rand_reset_test_seq_parameters)

  constraint reset_enable_c {reset_testing == ENABLE;}

  constraint reset_loops_c {num_reset_loops inside {[2 : 4]};}

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : pwrmgr_rst_safe_stress_all_with_rand_reset_test_seq_parameters


class pwrmgr_rst_safe_stress_all_with_rand_reset_vseq extends pwrmgr_rst_safe_stress_all_vseq;

  `uvm_object_utils(pwrmgr_rst_safe_stress_all_with_rand_reset_vseq)

  // Where the reset lands inside the work. The delay agent counts cycles of the always-on domain
  // the power-on reset belongs to, so a step is one of those cycles.
  //
  // The inherited range schedules the reset long after the last child has finished, where it
  // interrupts nothing. This spans the work instead: early enough to land in the first child, and
  // not beyond the longest whole workload.
  constraint rand_reset_delay_c {
    rand_reset_delay dist {
      [1 : 500]     :/ 2,
      [501 : 3000]  :/ 5,
      [3001 : 8000] :/ 3
    };
  }

  extern function new(string name = "");
  extern virtual task body();
endclass : pwrmgr_rst_safe_stress_all_with_rand_reset_vseq


function pwrmgr_rst_safe_stress_all_with_rand_reset_vseq::new(string name = "");
  super.new(name);
endfunction : new


task pwrmgr_rst_safe_stress_all_with_rand_reset_vseq::body();
  // The alert sender lives in the device's reset domain and the agent pinging it does not, so a
  // ping in flight when this sequence resets the device is never answered and is reported as a
  // timeout. Ping checking stays on elsewhere, where resets do not land at arbitrary points.
  cfg.en_scb_ping_chk = 1'b0;

  if (test_params == null) begin
    test_params = pwrmgr_rst_safe_stress_all_with_rand_reset_test_seq_parameters::type_id::create(
        "test_params");
  end
  super.body();
endtask : body
