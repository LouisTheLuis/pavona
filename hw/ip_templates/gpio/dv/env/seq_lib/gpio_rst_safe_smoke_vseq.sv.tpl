// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe smoke.
//
// One operation drives a pin pattern through the noise filter, waits for the resulting
// interrupt as a monitor transaction rather than by watching a pin, reads back the input and
// the interrupt state over the bus, and clears the interrupt. That is enough functional work
// for reset to land in the middle of something, which is what the reset-enabled form of this
// sequence needs in order to prove anything.
class ${module_instance_name}_rst_safe_smoke_vseq extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${module_instance_name}_rst_safe_smoke_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task run_one_operation();
endclass : ${module_instance_name}_rst_safe_smoke_vseq


function ${module_instance_name}_rst_safe_smoke_vseq::new(string name = "");
  super.new(name);
endfunction : new


task ${module_instance_name}_rst_safe_smoke_vseq::main_thread();
  // The stress wrapper runs sequences back to back without dut_init(), so the device may
  // still be driving the pins from the sequence before this one.
  release_device_outputs();

  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)
  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    run_one_operation();
  end
endtask : main_thread


task ${module_instance_name}_rst_safe_smoke_vseq::run_one_operation();
  // Which pins the testbench keeps. On a board with no weak pulls a pin neither end drives is
  // floating, and the x that produces reaches the device's own interrupt logic, so there the
  // testbench keeps every pin and the device drives none. The legacy smoke does the same thing
  // by always driving the whole port.
  bit [NUM_GPIOS-1:0] mask     = cfg.no_pulls ? '1 : config_params.intr_mask;
  bit [NUM_GPIOS-1:0] pu_mask  = pullup_mask();
  bit [NUM_GPIOS-1:0] pd_mask  = pulldown_mask();
  bit [TL_DW-1:0]     rd_data;
  // The pins the device drives. Everything the testbench drives is left to it, so the two
  // never contend; a pin driven from both ends resolves to x and the check on the net says so.
  bit [NUM_GPIOS-1:0] dut_pins = ~mask;

  // Rising-edge interrupts on the pins under test, and nothing else, so the interrupt that
  // arrives can only have come from the edge this operation creates. Level sources are left
  // off here because they re-assert as fast as software can clear them, which is a behavior
  // worth its own directed test rather than something to trip over in smoke.
  csr_wr(.ptr(ral.ctrl_en_input_filter), .value(config_params.filter_enable));
  csr_wr(.ptr(ral.intr_ctrl_en_rising), .value(mask));
  csr_wr(.ptr(ral.intr_enable), .value(mask));

  // Release the testbench's drive on the pins the device is about to drive, and settle low
  // on the ones it keeps. Order matters and is the real-world order: two drivers must never
  // be enabled on one net at the same time, and dut_init() left the testbench driving all of
  // them. Enabling the device's driver first resolves the net to x, which the check on the
  // net reports as contention.
  drive_pins(.value('0), .drive_en(mask), .pullup_en(pu_mask), .pulldown_en(pd_mask),
             .hold_cycles(2));

  // Now the device can drive the rest. This is a real GPIO arrangement rather than a
  // contrivance: some pins are inputs being watched for interrupts and some are outputs the
  // block is driving, and the driven values loop back through the same input path.
  csr_wr(.ptr(ral.direct_out), .value(config_params.gpio_i & dut_pins));
  csr_wr(.ptr(ral.direct_oe), .value(dut_pins));

  // Settle for longer than the filter window, so the starting point is a value the device
  // has certainly accepted whether or not the filter is enabled on a given pin.
  drive_pins(.value('0), .drive_en(mask), .pullup_en(pu_mask), .pulldown_en(pd_mask),
             .hold_cycles(FILTER_CYCLES + 2));

  // The edge. Held for the randomized settle time, which is sometimes shorter than the
  // filter window and sometimes longer, so a filtered pin sometimes does not see it at all.
  drive_pins(.value(mask), .drive_en(mask), .pullup_en(pu_mask), .pulldown_en(pd_mask),
             .hold_cycles(config_params.settle_cycles));

  // Hold long enough that every pin, filtered or not, has certainly passed the change
  // through. Without this the wait below could hang on a filtered pin whose edge was too
  // short to survive, which would be a testbench bug rather than a device failure.
  drive_pins(.value(mask), .drive_en(mask), .pullup_en(pu_mask), .pulldown_en(pd_mask),
             .hold_cycles(FILTER_CYCLES + 2));

  // Transaction-level synchronization. The interrupt arrives as a monitor observation; no
  // pin is sampled and no CSR is polled to find out that it happened.
  wait_for_interrupt(.mask(mask), .rising(1'b1));

  // Architectural read-back. The scoreboard checks both against the values it predicted from
  // the device's own filtered input, so the sequence does not compute an expectation.
  csr_rd(.ptr(ral.data_in), .value(rd_data));
  csr_rd(.ptr(ral.intr_state), .value(rd_data));
  csr_rd(.ptr(ral.direct_out), .value(rd_data));
  csr_rd(.ptr(ral.direct_oe), .value(rd_data));

  // Clear, and confirm the output drops. INTR_STATE is W1C and no level source is enabled,
  // so the bits stay clear rather than being re-set on the next cycle.
  csr_wr(.ptr(ral.intr_state), .value(mask));
  wait_for_interrupt(.mask(mask), .rising(1'b0));

  // A masked write, so the masked path is exercised rather than only the direct one. The
  // mask selects the upper half of the pins the device is driving.
  csr_wr(.ptr(ral.masked_out_upper),
         .value({dut_pins[NUM_GPIOS-1:16], ~config_params.gpio_i[NUM_GPIOS-1:16]}));

  // Leave interrupts disabled and the device driving nothing, so the next operation starts
  // from its own configuration rather than this one's leftovers.
  csr_wr(.ptr(ral.intr_enable), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_rising), .value('0));
  csr_wr(.ptr(ral.direct_oe), .value('0));
  drive_pins(.value('0), .drive_en('1), .pullup_en(pu_mask), .pulldown_en(pd_mask),
             .hold_cycles(2));
endtask : run_one_operation
