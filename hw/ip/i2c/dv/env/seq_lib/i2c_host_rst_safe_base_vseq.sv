// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_host_rst_safe_base_vseq extends i2c_rand_rst_safe_base_vseq;
  `uvm_object_utils(i2c_host_rst_safe_base_vseq)
  `uvm_object_new

  localparam bit [6:0] SmokeTargetAddr = 7'h55;

  virtual task initialize_host_mode();
    program_smoke_timing();

    ral.ctrl.enablehost.set(1'b1);
    ral.ctrl.enabletarget.set(1'b0);
    ral.ctrl.llpbk.set(1'b0);
    csr_update(.csr(ral.ctrl), .blocking(1));

    ral.ovrd.txovrden.set(1'b0);
    csr_update(.csr(ral.ovrd), .blocking(1));

    ral.fifo_ctrl.rxrst.set(1'b1);
    ral.fifo_ctrl.fmtrst.set(1'b1);
    ral.fifo_ctrl.acqrst.set(1'b1);
    ral.fifo_ctrl.txrst.set(1'b1);
    csr_update(.csr(ral.fifo_ctrl), .blocking(1));

    csr_wr(.ptr(ral.intr_enable), .value(1 << CmdComplete), .blocking(1));
    csr_wr(.ptr(ral.intr_state), .value('1), .blocking(1));
  endtask : initialize_host_mode

  virtual task write_fdata(bit [7:0] fbyte, bit start, bit stop, bit readb);
    csr_spinwait(.ptr(ral.status.fmtfull), .exp_data(1'b0));
    ral.fdata.fbyte.set(fbyte);
    ral.fdata.start.set(start);
    ral.fdata.stop.set(stop);
    ral.fdata.readb.set(readb);
    ral.fdata.rcont.set(1'b0);
    ral.fdata.nakok.set(1'b0);
    csr_update(.csr(ral.fdata), .blocking(1));
  endtask : write_fdata

  virtual task send_one_host_read(output bit [7:0] rdata);
    uvm_reg_data_t value;

    write_fdata({SmokeTargetAddr, i2c_pkg::READ}, 1'b1, 1'b0, 1'b0);
    write_fdata(8'd1, 1'b0, 1'b1, 1'b1);
    csr_spinwait(.ptr(ral.status.rxempty), .exp_data(1'b0));
    csr_rd(.ptr(ral.rdata), .value(value), .blocking(1));
    rdata = value[7:0];
    csr_spinwait(.ptr(ral.status.hostidle), .exp_data(1'b1));
    csr_spinwait(.ptr(ral.status.fmtempty), .exp_data(1'b1));
  endtask : send_one_host_read

  // Complete interrupt handling as part of the functional transaction. This
  // avoids a zero-delay polling worker that can flood the TL sequencer and
  // starve the main thread. Interrupt-pin prediction/observation remains a
  // scoreboard/monitor responsibility; this CSR access only acknowledges the
  // DUT event and does not pass interrupt state to the scoreboard.
  virtual task acknowledge_host_cmd_complete();
    uvm_reg_data_t intr_state;
    csr_spinwait(.ptr(ral.intr_state.cmd_complete), .exp_data(1'b1));
    csr_wr(.ptr(ral.intr_state), .value(1 << CmdComplete), .blocking(1));
  endtask : acknowledge_host_cmd_complete
endclass : i2c_host_rst_safe_base_vseq
