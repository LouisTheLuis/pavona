// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_inject_scramble_seed_vseq extends chip_sw_base_vseq;
  `uvm_object_utils(chip_sw_inject_scramble_seed_vseq)

  `uvm_object_new

  virtual task dut_init(string reset_kind = "HARD");
    super.dut_init(reset_kind);

    // Clear the OTP SRAM seed data to start from an empty state.
    for (int i = 0; i < otp_ctrl_reg_pkg::SramDataKeySeedSize; i += 8) begin
      cfg.mem_bkdr_util_h[Otp].write64(otp_ctrl_reg_pkg::SramDataKeySeedOffset + i, '0);
    end

    cfg.mem_bkdr_util_h[Otp].write64(otp_ctrl_reg_pkg::Secret1DigestOffset, '0);

    // make sure we are in prod state
    otp_write_lc_partition_state(cfg.mem_bkdr_util_h[Otp], LcStProd);
  endtask // dut_init

  virtual task body();
    super.body();

    `DV_SPINWAIT(wait(cfg.sw_logger_vif.printed_log ==
                      "Completed first phase, wait for reset");,
                 "timeout waiting for C side acknowledgement",
                 cfg.sw_test_timeout_ns)

    `uvm_info(`gfn, "Received C side acknowledgement", UVM_LOW)

    `DV_SPINWAIT(wait(cfg.sw_logger_vif.printed_log == "Hello World");,
             "timeout waiting for Hello World",
             cfg.sw_test_timeout_ns)
  endtask



endclass : chip_sw_inject_scramble_seed_vseq
