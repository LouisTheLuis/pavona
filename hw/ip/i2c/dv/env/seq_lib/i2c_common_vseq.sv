// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_common_vseq extends i2c_base_vseq;
  `uvm_object_utils(i2c_common_vseq)
  `uvm_object_new

  constraint num_trans_c { num_trans inside {[1:2]}; }

  // for this vseq, $value$plusargs "+en_scb=0" is defined in i2c_sim_cfg.hjson
  // disable i2c_monitor and i2c_scoreboard since they can not handle this test

  virtual task body();
    `uvm_info(`gfn, "\n--> start of i2c_common_vseq", UVM_DEBUG)
    run_common_vseq_wrapper(num_trans);
    `uvm_info(`gfn, "\n--> end of i2c_common_vseq", UVM_DEBUG)
  endtask : body

  virtual task post_start();
    // Clean up i2c.OVRD for CSR tests that may randomly write it. Leaving override enabled can
    // continuously reassert scl/sda interference interrupts during generic interrupt cleanup.
    if (common_seq_type inside {"", "same_csr_outstanding"}) begin
      // clear i2c.OVRDEN
      ral.ovrd.txovrden.set(1'b0);
      csr_update(ral.ovrd);
    end
    super.post_start();
  endtask
endclass : i2c_common_vseq
