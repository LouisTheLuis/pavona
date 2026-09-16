// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_lc_ctrl_program_error_vseq extends chip_sw_base_vseq;
  `uvm_object_utils(chip_sw_lc_ctrl_program_error_vseq)

  `uvm_object_new

  virtual task body();
    super.body();

    // This test injects a fault on purpose. The fatal alert it raises stays asserted
    // until reset, and some blocks raise their own alerts once escalation starts, so the
    // sweep at the end of cip_base_vseq would call every one of them unexpected.
    expect_fatal_alerts = 1'b1;

    // That same path re-initializes the chip once the body task exits, which resets it while
    // accesses are still in flight. pre_start has already done the initial init, so clearing
    // the bit here only stops the one at the end.
    do_dut_init = 1'b0;

    // Wait for C side to fully stabilize
    `DV_SPINWAIT(wait(cfg.sw_logger_vif.printed_log == "Begin life cycle transition");,
             "timeout waiting for C side acknowledgement",
             cfg.sw_test_timeout_ns)

    `DV_SPINWAIT(cfg.chip_vif.create_illegal_lc_request_for_otp();,
                 "timeout waiting for an lc_program request for otp_ctrl",
                 cfg.sw_test_timeout_ns)
  endtask
endclass
