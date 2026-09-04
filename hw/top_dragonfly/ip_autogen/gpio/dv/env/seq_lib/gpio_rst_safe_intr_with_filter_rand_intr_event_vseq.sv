// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Programs the interrupt registers and the filter, then moves every pin on its own schedule,
// with the stable time per pin drawn either side of the filter window so that some changes are
// passed and some are swallowed.
//
// The legacy sequence built its own DATA_IN and INTR_STATE predictions and compared reads
// against them, and ran with the scoreboard disabled. Neither is carried over. The reset-safe
// scoreboard models the filter and the interrupt logic from the probe, so the sequence drives
// and reads and the checking happens in one place.
class gpio_rst_safe_intr_with_filter_config_parameters
    extends gpio_rst_safe_config_parameters;
  `uvm_object_utils(gpio_rst_safe_intr_with_filter_config_parameters)

  // Cycles each pin holds its value for. Independent per pin, which is what makes the pins
  // change at unrelated times rather than as one word.
  rand int unsigned    stable_cycles_per_pin[NUM_GPIOS];

  // Value written to whichever interrupt registers this operation selects.
  rand bit [TL_DW-1:0] intr_reg_value;

  // Number of pin changes in one operation.
  rand int unsigned    num_pin_steps;

  // Whether this operation reprograms the filter before driving.
  rand bit             program_filter;

  // The filter passes a change only after the input has been stable for the whole window, so
  // a hold drawn from below it is a change the device should swallow and one drawn at or
  // above it is a change it should pass. Most of the weight sits below, because that is the
  // case the filter exists for.
  constraint stable_cycles_per_pin_c {
    foreach (stable_cycles_per_pin[i]) {
      stable_cycles_per_pin[i] dist {
        [1:FILTER_CYCLES-1]     :/ 70,
        [FILTER_CYCLES:2*FILTER_CYCLES] :/ 30
      };
    }
  }

  constraint num_pin_steps_c {
    num_pin_steps inside {[5:15]};
  }

  constraint reg_write_mask_c {
    reg_write_mask != '0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_intr_with_filter_config_parameters


class gpio_rst_safe_intr_with_filter_rand_intr_event_vseq
    extends gpio_rand_rst_safe_base_vseq;
  `uvm_object_utils(gpio_rst_safe_intr_with_filter_rand_intr_event_vseq)

  // The pin state the sequence is currently presenting, carried across operations so that a
  // new operation starts from what the device is already seeing rather than from a jump.
  protected bit [NUM_GPIOS-1:0] driven_value;

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task program_interrupt_registers();
  extern protected task run_pin_schedule();
  extern protected task read_input_and_interrupt_state();
endclass : gpio_rst_safe_intr_with_filter_rand_intr_event_vseq


function gpio_rst_safe_intr_with_filter_rand_intr_event_vseq::new(
    string name = "");
  super.new(name);
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_intr_with_filter_config_parameters::get_type());
endfunction : new


task gpio_rst_safe_intr_with_filter_rand_intr_event_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  driven_value = '0;

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    gpio_rst_safe_intr_with_filter_config_parameters params;

    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `downcast(params, config_params)

    // The device stops driving before the testbench does, so the pins carry one value.
    csr_wr(.ptr(ral.direct_oe), .value('0));

    if (params.program_filter) begin
      csr_wr(.ptr(ral.ctrl_en_input_filter), .value(config_params.filter_enable));
    end
    program_interrupt_registers();
    read_input_and_interrupt_state();

    run_pin_schedule();
    read_input_and_interrupt_state();
  end
endtask : main_thread


task gpio_rst_safe_intr_with_filter_rand_intr_event_vseq::
    program_interrupt_registers();
  gpio_rst_safe_intr_with_filter_config_parameters params;
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


task gpio_rst_safe_intr_with_filter_rand_intr_event_vseq::run_pin_schedule();
  gpio_rst_safe_intr_with_filter_config_parameters params;
  int unsigned remaining[NUM_GPIOS];
  `downcast(params, config_params)

  foreach (remaining[i]) remaining[i] = params.stable_cycles_per_pin[i];

  // Each pin has its own countdown. The pins are driven as one word, so the word is held for
  // the shortest countdown still running, and only the pins whose countdown reaches zero
  // change when it expires. That gives per pin timing through an agent that drives the pins
  // together.
  for (int unsigned step = 0; step < params.num_pin_steps; step++) begin
    int unsigned hold = remaining[0];

    foreach (remaining[i]) if (remaining[i] < hold) hold = remaining[i];

    drive_pins(.value(driven_value),
               .drive_en('1),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(hold));

    foreach (remaining[i]) begin
      remaining[i] -= hold;
      if (remaining[i] == 0) begin
        driven_value[i] = ~driven_value[i];
        remaining[i]    = params.stable_cycles_per_pin[i];
      end
    end
  end
endtask : run_pin_schedule


task gpio_rst_safe_intr_with_filter_rand_intr_event_vseq::
    read_input_and_interrupt_state();
  bit [TL_DW-1:0] rd_data;

  csr_rd(.ptr(ral.data_in),    .value(rd_data));
  csr_rd(.ptr(ral.intr_state), .value(rd_data));
endtask : read_input_and_interrupt_state
