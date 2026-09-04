// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Programs a random set of the interrupt control registers, then toggles the inputs and reads
// and clears INTR_STATE at the same time.
//
// The concurrency is the point of the sequence. Pin activity is raising interrupt bits while
// software is clearing them, so a hardware set and a software write-one-to-clear land in the
// same cycle and the design has to arbitrate between them.
class gpio_rst_safe_rand_intr_trigger_config_parameters
    extends gpio_rst_safe_config_parameters;
  `uvm_object_utils(gpio_rst_safe_rand_intr_trigger_config_parameters)

  // The value written to whichever interrupt control registers this operation selects.
  rand bit [TL_DW-1:0] intr_reg_value;

  // How many times the driving arm changes the pins before the operation ends.
  rand int unsigned    num_pin_toggles;

  // Cycles one pin state is held. Deliberately allowed to be shorter than the filter window,
  // so that some changes are swallowed and some get through.
  rand int unsigned    toggle_hold_cycles;

  // The reading arm. Which register it reads, and whether it follows the read with a clear.
  rand bit             read_data_in;
  rand bit             do_intr_state_clear;
  rand bit [TL_DW-1:0] intr_state_clear_mask;

  constraint num_pin_toggles_c {
    num_pin_toggles inside {[5:20]};
  }

  constraint toggle_hold_cycles_c {
    toggle_hold_cycles inside {[1:5]};
  }

  // The legacy sequence reads INTR_STATE nine times out of ten and DATA_IN the rest, so that
  // most of the bus traffic is on the register the operation is about.
  constraint read_data_in_c {
    read_data_in dist {1'b0 :/ 9, 1'b1 :/ 1};
  }

  // Only the five interrupt control registers are programmed here. INTR_STATE is left to the
  // reading arm, which is what puts the clear next to a hardware set.
  constraint reg_write_mask_c {
    reg_write_mask[5] == 1'b0;
    reg_write_mask != '0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_rand_intr_trigger_config_parameters


class gpio_rst_safe_rand_intr_trigger_vseq
    extends gpio_rand_rst_safe_base_vseq;
  `uvm_object_utils(gpio_rst_safe_rand_intr_trigger_vseq)

  // Set by the driving arm when it has finished, so the reading arm stops with it. The
  // reading arm has no count of its own: it runs for as long as there is pin activity to
  // race against.
  protected bit toggling_done;

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task program_interrupt_registers();
  extern protected task drive_pin_toggles();
  extern protected task read_and_clear_intr_state();
endclass : gpio_rst_safe_rand_intr_trigger_vseq


function gpio_rst_safe_rand_intr_trigger_vseq::new(string name = "");
  super.new(name);
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_rand_intr_trigger_config_parameters::get_type());
endfunction : new


task gpio_rst_safe_rand_intr_trigger_vseq::main_thread();
  // The stress wrapper runs sequences back to back without dut_init(), so the device may
  // still be driving the pins from the sequence before this one.
  release_device_outputs();

  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(config_params)

    program_interrupt_registers();

    toggling_done = 1'b0;
    fork
      drive_pin_toggles();
      read_and_clear_intr_state();
    join
  end
endtask : main_thread


task gpio_rst_safe_rand_intr_trigger_vseq::program_interrupt_registers();
  gpio_rst_safe_rand_intr_trigger_config_parameters params;
  `downcast(params, config_params)

  if (config_params.reg_write_mask[0]) begin
    csr_wr(.ptr(ral.intr_enable), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[1]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_falling), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[2]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_rising), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[3]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvllow), .value(params.intr_reg_value));
  end
  if (config_params.reg_write_mask[4]) begin
    csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value(params.intr_reg_value));
  end
endtask : program_interrupt_registers


task gpio_rst_safe_rand_intr_trigger_vseq::drive_pin_toggles();
  gpio_rst_safe_rand_intr_trigger_config_parameters outer;
  gpio_rst_safe_rand_intr_trigger_config_parameters toggle;
  `downcast(outer, config_params)

  // A private object per arm. Re-randomizing config_params here would change values under the
  // reading arm, which is running at the same time.
  toggle = gpio_rst_safe_rand_intr_trigger_config_parameters::type_id::
      create("toggle");

  for (int unsigned i = 0; i < outer.num_pin_toggles; i++) begin
    `DV_CHECK_RANDOMIZE_FATAL(toggle)
    // The board topology belongs to the epoch, not to the toggle, so it comes from the
    // operation's own parameters and stays put while the pins move.
    drive_pins(.value(toggle.gpio_i),
               .drive_en('1),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(toggle.toggle_hold_cycles));
  end

  toggling_done = 1'b1;
endtask : drive_pin_toggles


task gpio_rst_safe_rand_intr_trigger_vseq::read_and_clear_intr_state();
  gpio_rst_safe_rand_intr_trigger_config_parameters rd;

  rd = gpio_rst_safe_rand_intr_trigger_config_parameters::type_id::
      create("rd");

  // No wait paces this loop. Each bus access takes its own cycles, and the pins are moving
  // throughout, so reads and clears land at unrelated points in the pin activity without a
  // delay being used to arrange it.
  do begin
    bit [TL_DW-1:0] rd_data;

    `DV_CHECK_RANDOMIZE_FATAL(rd)
    if (rd.read_data_in) csr_rd(.ptr(ral.data_in),    .value(rd_data));
    else                 csr_rd(.ptr(ral.intr_state), .value(rd_data));

    if (rd.do_intr_state_clear) begin
      // W1C, so this clears whichever bits the mask selects.
      csr_wr(.ptr(ral.intr_state), .value(rd.intr_state_clear_mask));
    end
  end while (!toggling_done);
endtask : read_and_clear_intr_state
