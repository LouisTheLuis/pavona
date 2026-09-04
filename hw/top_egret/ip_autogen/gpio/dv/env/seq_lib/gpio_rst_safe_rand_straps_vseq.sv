// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Requests a strap sample and then checks that nothing afterwards disturbs it: not letting go
// of the inputs, and not driving the device's own outputs onto the same pins.
//
// The legacy sequence ended by resetting the device itself and reading the strap registers
// again to see them cleared. That step is not carried over. Reset belongs to
// reset_trigger_thread(), and what it was checking is covered without it: every epoch starts
// from reset, and the first read in an epoch sees the reset state.
//
// Repeating the operation inside one epoch is deliberate. The device samples on
// `strap_en && !valid`, so every request after the first has to be refused, and the scoreboard
// fails a second sample taken in one epoch.
class gpio_rst_safe_rand_straps_config_parameters
    extends gpio_rst_safe_config_parameters;
  `uvm_object_utils(gpio_rst_safe_rand_straps_config_parameters)

  // Output drive programmed after the sample, to confirm it does not reach the strap
  // registers.
  rand bit [TL_DW-1:0] out_value;
  rand bit [TL_DW-1:0] oe_value;

  // The workload here is longer and more uniform than the base sequence's, because every
  // operation holds the pins still for the filter twice over before it touches a register.
  // Reset can therefore be given a later window and still land inside it.
  constraint reset_delay_c {
    reset_delay dist {
      [30:100]  :/ 3,
      [101:220] :/ 5,
      [221:300] :/ 2
    };
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_rand_straps_config_parameters


class gpio_rst_safe_rand_straps_vseq
    extends gpio_rand_rst_safe_base_vseq;
  `uvm_object_utils(gpio_rst_safe_rand_straps_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task read_strap_registers();
endclass : gpio_rst_safe_rand_straps_vseq


function gpio_rst_safe_rand_straps_vseq::new(string name = "");
  super.new(name);
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_rand_straps_config_parameters::get_type());
endfunction : new


task gpio_rst_safe_rand_straps_vseq::main_thread();
  // The stress wrapper runs sequences back to back without dut_init(), so the device may
  // still be driving the pins from the sequence before this one.
  release_device_outputs();

  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    gpio_rst_safe_rand_straps_config_parameters params;

    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `downcast(params, config_params)

    // The device samples its filtered input, so the pins are held long enough for the filter
    // to have passed them before the request is made. Without that the sample would be
    // checked against an input the device had not finished accepting.
    drive_pins(.value(config_params.gpio_i),
               .drive_en('1),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(FILTER_CYCLES + 2));

    // Request the sample with the same pin state still applied.
    drive_pins(.value(config_params.gpio_i),
               .drive_en('1),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(2),
               .strap_en_pulse(1'b1));

    read_strap_registers();

    // Letting go of the pins changes the filtered input. The strap registers hold a snapshot
    // and must not follow it.
    drive_pins(.value('0),
               .drive_en('0),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(FILTER_CYCLES + 2));

    read_strap_registers();

    // The device driving its own pins changes the filtered input again, from the other side.
    // The snapshot must not follow that either.
    csr_wr(.ptr(ral.direct_out), .value(params.out_value));
    csr_wr(.ptr(ral.direct_oe),  .value(params.oe_value));

    drive_pins(.value('0),
               .drive_en('0),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(FILTER_CYCLES + 2));

    read_strap_registers();

    // Hand the pins back, so the next operation starts from the device driving nothing.
    csr_wr(.ptr(ral.direct_oe), .value('0));
  end
endtask : main_thread


task gpio_rst_safe_rand_straps_vseq::read_strap_registers();
  bit [TL_DW-1:0] rd_data;

  // Read rather than mirrored with UVM_CHECK. The scoreboard owns the comparison, against a
  // model built from what the probe saw the device latch, so a check here would only compare
  // the mirror against itself.
  csr_rd(.ptr(ral.hw_straps_data_in),       .value(rd_data));
  csr_rd(.ptr(ral.hw_straps_data_in_valid), .value(rd_data));
endtask : read_strap_registers
