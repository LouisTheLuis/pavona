// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_target_rst_safe_smoke_test_seq_parameters extends i2c_rst_safe_test_seq_parameters;
  `uvm_object_utils(i2c_target_rst_safe_smoke_test_seq_parameters)
  constraint reset_enable_c {reset_testing == DISABLE;}
  constraint reset_loops_c {num_reset_loops == 1;}
  constraint num_trans_c {num_trans inside {[10 : 20]};}
  `uvm_object_new
endclass : i2c_target_rst_safe_smoke_test_seq_parameters

class i2c_target_rst_safe_smoke_vseq extends i2c_target_rst_safe_base_vseq;
  `uvm_object_utils(i2c_target_rst_safe_smoke_vseq)

  function new(string name = "");
    super.new(name);
    i2c_rst_safe_test_seq_parameters::type_id::set_type_override(
        i2c_target_rst_safe_smoke_test_seq_parameters::get_type());
  endfunction : new

  virtual task main_thread();
    initialize_target_mode();

    for (int unsigned trans = 0; trans < test_params.num_trans; trans++) begin
      bit [7:0] data = $urandom;
      if (trans[0]) drive_target_read(data);
      else drive_target_write(data);
      csr_spinwait(.ptr(ral.status.targetidle), .exp_data(1'b1));
      drain_acq_fifo();
    end

    // Allow the final monitor and scoreboard transactions to drain through their
    // FIFOs without reading a signal-level clock interface from the sequence.
    begin
      delay_seq del_seq = delay_seq::type_id::create("del_seq:target_final_drain");
      del_seq.delay_time_steps = 1_000;
      del_seq.start(p_sequencer.delay_sequencer_h);
    end
  endtask : main_thread
endclass : i2c_target_rst_safe_smoke_vseq
