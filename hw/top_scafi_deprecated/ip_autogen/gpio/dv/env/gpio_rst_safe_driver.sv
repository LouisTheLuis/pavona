// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe driver for the testbench side of the GPIO pins and for the strap trigger.
//
// The base class terminates drive_item() wherever it happens to be when reset asserts, so
// the driver keeps no state between items beyond what reset_interface_and_driver() can put
// back.
class gpio_rst_safe_driver extends dv_rst_safe_base_driver #(
    .ITEM_T(gpio_seq_item),
    .CFG_T (gpio_agent_cfg)
  );
  `uvm_component_utils(gpio_rst_safe_driver)
  `uvm_component_new

  extern virtual task get_and_drive();
  extern virtual function void reset_interface_and_driver();
  extern virtual task drive_item(gpio_seq_item item);
endclass : gpio_rst_safe_driver


task gpio_rst_safe_driver::get_and_drive();
  gpio_seq_item req;

  forever begin
    get_next_item(req);
    drive_item(req);
    item_done();
  end
endtask : get_and_drive


task gpio_rst_safe_driver::drive_item(gpio_seq_item item);
  // Align to the clocking block, not to the raw posedge. A process resumed by
  // @(posedge clk) runs in the Active region, alongside the device's own flops, so a pin
  // assignment made there races the edge that samples it. The clocking block resumes in the
  // Observed region, after the device has sampled, which makes the drive unambiguous.
  @(cfg.reset_domain.clk_rst_vif.cb);

  if (item.drive_offset_ps > 0) begin
    // A deliberate asynchronous input change. The device input path either has a two flop
    // synchronizer or does not, and this is the stimulus that tells the two apart. The
    // offset comes from the item rather than from a delay written into a sequence.
    #(item.drive_offset_ps * 1ps);
  end

  cfg.gpio_vif.set_pullup_en(item.pullup_en);
  cfg.gpio_vif.set_pulldown_en(item.pulldown_en);
  cfg.gpio_vif.pins_o  = item.gpio_i;
  cfg.gpio_vif.pins_oe = item.gpio_i_oe;

  if (item.strap_en_pulse) begin
    // strap_en_i is specified as a single cycle pulse from the power manager. Drive exactly
    // that, so a sequence cannot accidentally hold it and hide the once-per-reset latch.
    cfg.straps_vif_inst.tb_port.strap_en = 1'b1;
    @(cfg.reset_domain.clk_rst_vif.cb);
    cfg.straps_vif_inst.tb_port.strap_en = 1'b0;
  end

  repeat (item.hold_cycles) @(cfg.reset_domain.clk_rst_vif.cb);
endtask : drive_item


function void gpio_rst_safe_driver::reset_interface_and_driver();
  // Clear the stimulus this testbench was applying. Reset must not leave the pin value or the
  // strap trigger set from the epoch that ended.
  cfg.gpio_vif.pins_o = '0;
  cfg.straps_vif_inst.tb_port.strap_en = 1'b0;

  // Restore the board's weak pulls rather than clearing them. Once the drive is released the
  // pulls are the only thing holding the net, and this function also runs at power-on reset,
  // before any sequence has run. Clearing them here, or leaving them at their power-on zero,
  // leaves the net floating out of every reset; the undriven value reaches DATA_IN and the
  // interrupt logic through the filter and shows up as an unknown on intr_gpio_o a long way
  // from its cause.
  cfg.gpio_vif.set_pullup_en(cfg.default_pullup_en);
  cfg.gpio_vif.set_pulldown_en(cfg.default_pulldown_en);

  // Whether to keep driving depends on what the board provides. With a weak pull the drive is
  // released, so the pins sit at the board's idle value and the first sequence decides what
  // happens next. With no pull there is nothing to hold them, and a released pin floats from
  // the moment reset deasserts until a sequence first drives, which is long enough for the
  // unknown to reach the device. There the testbench keeps driving the value it just cleared.
  if (cfg.default_pullup_en == '0 && cfg.default_pulldown_en == '0) begin
    cfg.gpio_vif.drive_en('1);
  end else begin
    cfg.gpio_vif.drive_en('0);
  end
endfunction : reset_interface_and_driver
