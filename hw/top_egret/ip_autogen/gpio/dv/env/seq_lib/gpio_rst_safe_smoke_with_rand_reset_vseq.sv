// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-enabled form of the reset-safe smoke.
//
// The workload is identical; only the reset policy differs. Keeping it a separate class
// rather than a plusarg gives the two forms distinct dvsim entries and distinct sequence
// names, which is what the testplan mapping and the failure triage both need.
class gpio_rst_safe_smoke_with_rand_reset_test_seq_parameters
    extends gpio_rst_safe_test_seq_parameters;
  `uvm_object_utils(gpio_rst_safe_smoke_with_rand_reset_test_seq_parameters)

  constraint reset_enable_c {
    reset_testing == ENABLE;
  }

  constraint reset_loops_c {
    num_reset_loops inside {[2:4]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_smoke_with_rand_reset_test_seq_parameters


class gpio_rst_safe_smoke_with_rand_reset_config_parameters
    extends gpio_rst_safe_config_parameters;
  `uvm_object_utils(gpio_rst_safe_smoke_with_rand_reset_config_parameters)

  // The inherited bound is already derived from this sequence's own measured workload, so
  // there is nothing to narrow here. Weight it toward the upper part of that range so reset
  // lands as late in the workload as the bound allows.
  constraint reset_delay_c {
    reset_delay dist {
      [20:60]   :/ 1,
      [61:140]  :/ 4,
      [141:180] :/ 5
    };
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_smoke_with_rand_reset_config_parameters


class gpio_rst_safe_smoke_with_rand_reset_vseq
    extends gpio_rst_safe_smoke_vseq;
  `uvm_object_utils(gpio_rst_safe_smoke_with_rand_reset_vseq)

  extern function new(string name = "");
endclass : gpio_rst_safe_smoke_with_rand_reset_vseq


function gpio_rst_safe_smoke_with_rand_reset_vseq::new(string name = "");
  super.new(name);
  gpio_rst_safe_test_seq_parameters::type_id::set_type_override(
      gpio_rst_safe_smoke_with_rand_reset_test_seq_parameters::get_type());
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_smoke_with_rand_reset_config_parameters::get_type());
endfunction : new
