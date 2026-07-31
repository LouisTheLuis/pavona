// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_host_rst_safe_smoke_test_seq_parameters extends i2c_rst_safe_test_seq_parameters;
  `uvm_object_utils(i2c_host_rst_safe_smoke_test_seq_parameters)
  constraint reset_enable_c {reset_testing == DISABLE;}
  constraint reset_loops_c {num_reset_loops == 1;}
  constraint num_trans_c {num_trans inside {[50 : 100]};}
  `uvm_object_new
endclass : i2c_host_rst_safe_smoke_test_seq_parameters

class i2c_host_rst_safe_smoke_vseq extends i2c_host_rst_safe_base_vseq;
  `uvm_object_utils(i2c_host_rst_safe_smoke_vseq)

  function new(string name = "");
    super.new(name);
    i2c_rst_safe_test_seq_parameters::type_id::set_type_override(
        i2c_host_rst_safe_smoke_test_seq_parameters::get_type());
  endfunction : new

  virtual task main_thread();
    i2c_base_seq target_responder = i2c_base_seq::type_id::create("target_responder");
    bit responder_done = 1'b0;

    initialize_host_mode();

    // The reactive target is owned by this main-thread pass. Normal completion
    // terminates and joins it explicitly after the DUT reports the bus idle;
    // reset assertion stops it in the reset-safe agent before the base sequence
    // kills this main thread.
    fork
      begin
        target_responder.start(p_sequencer.i2c_sequencer_h);
        responder_done = 1'b1;
      end
    join_none

    repeat (test_params.num_trans) begin
      bit [7:0] rdata;
      send_one_host_read(rdata);
      acknowledge_host_cmd_complete();
    end

    // i2c_base_seq::seq_stop() can remain blocked in its legacy graceful-stop
    // path even after the final transfer reaches STOP. The functional loop has
    // already observed hostidle, fmtempty and CmdComplete, so it is safe to
    // terminate only this owned responder sequence here. Do not stop every
    // sequence on the agent sequencer as part of normal completion.
    target_responder.kill();
    wait (responder_done);
  endtask : main_thread
endclass : i2c_host_rst_safe_smoke_vseq
