// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_target_rst_safe_base_vseq extends i2c_rand_rst_safe_base_vseq;
  `uvm_object_utils(i2c_target_rst_safe_base_vseq)
  `uvm_object_new

  localparam bit [6:0] SmokeTargetAddr = 7'h55;

  virtual task initialize_target_mode();
    // Target FSM setup/hold transitions depend on TIMING0..4 just as host
    // generation does. Leaving these at reset values causes the target to miss
    // the transfer and release SDA, which appears as 8'hff on target reads.
    program_smoke_timing();

    ral.ctrl.enablehost.set(1'b0);
    ral.ctrl.enabletarget.set(1'b1);
    ral.ctrl.llpbk.set(1'b0);
    ral.ctrl.ack_ctrl_en.set(1'b0);
    csr_update(.csr(ral.ctrl), .blocking(1));

    ral.target_id.address0.set(SmokeTargetAddr);
    ral.target_id.mask0.set(7'h7f);
    ral.target_id.address1.set(7'h2a);
    ral.target_id.mask1.set(7'h7f);
    csr_update(.csr(ral.target_id), .blocking(1));

    ral.host_timeout_ctrl.set('1);
    csr_update(.csr(ral.host_timeout_ctrl), .blocking(1));

    ral.fifo_ctrl.rxrst.set(1'b1);
    ral.fifo_ctrl.fmtrst.set(1'b1);
    ral.fifo_ctrl.acqrst.set(1'b1);
    ral.fifo_ctrl.txrst.set(1'b1);
    csr_update(.csr(ral.fifo_ctrl), .blocking(1));

    csr_wr(.ptr(ral.intr_enable), .value('0), .blocking(1));
    csr_wr(.ptr(ral.intr_state), .value('1), .blocking(1));
  endtask : initialize_target_mode

  function automatic i2c_item make_driver_item(drv_type_e drv_type, bit [7:0] wdata = '0);
    i2c_item item = i2c_item::type_id::create("driver_item");
    item.drv_type = drv_type;
    item.wdata = wdata;
    return item;
  endfunction : make_driver_item

  virtual task drive_target_write(bit [7:0] data);
    i2c_target_base_seq host_seq = i2c_target_base_seq::type_id::create("target_write_host_seq");
    host_seq.req_q.push_back(make_driver_item(HostStart));
    host_seq.req_q.push_back(make_driver_item(HostData, {SmokeTargetAddr, i2c_pkg::WRITE}));
    host_seq.req_q.push_back(make_driver_item(HostData, data));
    host_seq.req_q.push_back(make_driver_item(HostStop));
    host_seq.start(p_sequencer.i2c_sequencer_h);
  endtask : drive_target_write

  virtual task drive_target_read(bit [7:0] data);
    i2c_target_base_seq host_seq = i2c_target_base_seq::type_id::create("target_read_host_seq");
    csr_wr(.ptr(ral.txdata), .value(data), .blocking(1));
    host_seq.req_q.push_back(make_driver_item(HostStart));
    host_seq.req_q.push_back(make_driver_item(HostData, {SmokeTargetAddr, i2c_pkg::READ}));
    host_seq.req_q.push_back(make_driver_item(HostNAck));
    host_seq.req_q.push_back(make_driver_item(HostStop));
    host_seq.start(p_sequencer.i2c_sequencer_h);
  endtask : drive_target_read

  virtual task drain_acq_fifo();
    uvm_reg_data_t acq_level;
    do begin
      csr_rd(.ptr(ral.target_fifo_status.acqlvl), .value(acq_level), .blocking(1));
      repeat (acq_level) begin
        uvm_reg_data_t acq_data;
        csr_rd(.ptr(ral.acqdata), .value(acq_data), .blocking(1));
      end
    end while (acq_level != 0);
  endtask : drain_acq_fifo
endclass : i2c_target_rst_safe_base_vseq
