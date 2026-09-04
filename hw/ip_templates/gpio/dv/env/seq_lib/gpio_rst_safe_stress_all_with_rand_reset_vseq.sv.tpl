// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-enabled variant of ${module_instance_name}_rst_safe_stress_all_vseq. Kept in its own
// file so that the two stress-all entry points map to distinct dvsim test names and sequence
// classes.
class ${module_instance_name}_rst_safe_stress_all_with_rand_reset_test_seq_parameters
    extends ${module_instance_name}_rst_safe_stress_all_test_seq_parameters;
  `uvm_object_utils(
      ${module_instance_name}_rst_safe_stress_all_with_rand_reset_test_seq_parameters)

  constraint reset_enable_c {
    reset_testing == ENABLE;
  }

  constraint reset_loops_c {
    num_reset_loops inside {[2:4]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_stress_all_with_rand_reset_test_seq_parameters


class ${module_instance_name}_rst_safe_stress_all_with_rand_reset_vseq
    extends ${module_instance_name}_rst_safe_stress_all_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_stress_all_with_rand_reset_vseq)

  // Clock cycles the reset thread waits. The bound comes from the shortest workload the
  // wrapper can produce, not from the typical one, because a delay that outlives the workload
  // produces no reset during functional work at all and the base class treats that as an
  // error.
  //
  // The monitor reports the longest reset epoch of every run. Over four hundred epochs those
  // ranged from sixty four cycles to about ninety thousand, with a median near four hundred
  // and a fifth percentile near one hundred and fifty. A run whose longest epoch is sixty four
  // cycles is the one that has to be covered, so the whole range sits below it. Reset then
  // lands early in a long epoch, which is the same trade the base sequence makes.
  constraint rand_reset_delay_c {
    rand_reset_delay inside {[20:60]};
  }

  extern function new(string name = "");
  extern virtual task body();
endclass : ${module_instance_name}_rst_safe_stress_all_with_rand_reset_vseq


function ${module_instance_name}_rst_safe_stress_all_with_rand_reset_vseq::new(string name = "");
  super.new(name);
endfunction : new


task ${module_instance_name}_rst_safe_stress_all_with_rand_reset_vseq::body();
  if (test_params == null) begin
    test_params =
        ${module_instance_name}_rst_safe_stress_all_with_rand_reset_test_seq_parameters::
            type_id::create("test_seq_parameters");
  end
  super.body();
endtask : body
