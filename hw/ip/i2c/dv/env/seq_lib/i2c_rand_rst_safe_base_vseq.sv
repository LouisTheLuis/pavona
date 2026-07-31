// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_rst_safe_test_seq_parameters extends dv_test_seq_parameters;
  `uvm_object_utils(i2c_rst_safe_test_seq_parameters)

  constraint reset_enable_c {reset_testing inside {DISABLE, ENABLE};}
  constraint reset_loops_c {
    if (reset_testing == ENABLE)
    num_reset_loops inside {[2 : 4]};
    else
    num_reset_loops == 1;
  }

  `uvm_object_new
endclass : i2c_rst_safe_test_seq_parameters

class i2c_rand_rst_safe_base_vseq extends cip_rand_rst_safe_base_vseq #(
    .RAL_T              (i2c_reg_block),
    .CFG_T              (i2c_env_cfg),
    .COV_T              (i2c_env_cov),
    .VIRTUAL_SEQUENCER_T(i2c_virtual_sequencer),
    .TEST_PARAMS_T      (i2c_rst_safe_test_seq_parameters),
    .CONFIG_PARAMS_T    (dv_config_parameters)
);
  `uvm_object_utils(i2c_rand_rst_safe_base_vseq)
  `uvm_object_new

  constraint rand_reset_delay_c {
    rand_reset_delay dist {
      [        1 :      1_000] :/ 1,
      [    1_001 :    100_000] :/ 4,
      [  100_001 :  1_000_000] :/ 4,
      [1_000_001 : 10_000_000] :/ 1
    };
  }

  // Program the fixed DUT timing used by the reset-safe functional smokes.
  // The matching agent timing is build-time configuration in
  // i2c_rst_safe_base_test. Both host and target modes require these DUT
  // registers: target-mode state transitions use the hold/setup counters too.
  virtual task program_smoke_timing();
    ral.timing0.tlow.set(10);
    ral.timing0.thigh.set(12);
    csr_update(.csr(ral.timing0), .blocking(1));
    ral.timing1.t_f.set(2);
    ral.timing1.t_r.set(2);
    csr_update(.csr(ral.timing1), .blocking(1));
    ral.timing2.thd_sta.set(5);
    ral.timing2.tsu_sta.set(5);
    csr_update(.csr(ral.timing2), .blocking(1));
    ral.timing3.thd_dat.set(2);
    ral.timing3.tsu_dat.set(2);
    csr_update(.csr(ral.timing3), .blocking(1));
    ral.timing4.tsu_sto.set(5);
    ral.timing4.t_buf.set(8);
    csr_update(.csr(ral.timing4), .blocking(1));
  endtask : program_smoke_timing

  virtual task post_start();
    // Keep all functional CSR activity inside main_thread(), where the reset-safe
    // base can terminate it as a unit.
    do_clear_all_interrupts = 1'b0;
    super.post_start();
  endtask : post_start

  virtual task reset_trigger_thread();
    delay_seq del_seq = delay_seq::type_id::create("del_seq:reset_trigger");
    reset_seq rst_seq;

    del_seq.delay_time_steps = rand_reset_delay;
    del_seq.start(p_sequencer.delay_sequencer_h);
    rst_seq = reset_seq::type_id::create("rst_seq");
    rst_seq.start(p_sequencer.clk_rst_sequencer_h);
  endtask : reset_trigger_thread

  virtual task dut_init();
    // Each main_thread pass performs mode-specific initialization from reset state.
  endtask : dut_init

  virtual task main_thread();
    `uvm_fatal(`gfn, "Derived I2C reset-safe sequence must implement main_thread()")
  endtask : main_thread

  virtual function void handle_reset_assertion();
    super.handle_reset_assertion();
  endfunction : handle_reset_assertion
endclass : i2c_rand_rst_safe_base_vseq
