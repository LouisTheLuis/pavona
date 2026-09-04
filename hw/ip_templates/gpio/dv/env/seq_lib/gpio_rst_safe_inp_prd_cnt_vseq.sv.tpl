// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
<%
  vseq_name = f"{module_instance_name}_rst_safe_inp_prd_cnt_vseq"
%>\
% if num_inp_period_counters > 0:

// Drives input patterns at one selected pin and lets one input period counter measure them.
//
// The sequence asserts nothing about the measured value. It configures a counter, produces a
// pattern, and reads the result; the scoreboard predicts what the counter should have
// measured from the same edges the device saw and compares. That is the difference from the
// legacy sequence, which carried its own expected values for a handful of hand-computed
// cases and therefore only checked the cases someone had worked out in advance.
class ${vseq_name} extends ${module_instance_name}_rand_rst_safe_base_vseq;
  `uvm_object_utils(${vseq_name})

  extern function new(string name = "");
  extern virtual task main_thread();

  extern protected task configure_counter(int unsigned index, bit continuous, bit polarity,
                                          int unsigned input_index, int unsigned prescaler);
  extern protected task disable_counter(int unsigned index);
  extern protected task drive_pulse(int unsigned input_index, bit [NUM_GPIOS-1:0] others,
                                    int unsigned high_cycles, int unsigned low_cycles);
endclass : ${vseq_name}


function ${vseq_name}::new(string name = "");
  super.new(name);
endfunction : new


task ${vseq_name}::main_thread();
  // The stress wrapper runs sequences back to back without dut_init(), so the device may
  // still be driving the pins from the sequence before this one.
  release_device_outputs();

  `uvm_info(`gfn, $sformatf("Running %0d counter measurements", test_params.num_trans), UVM_LOW)

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    int unsigned cnt_idx;
    int unsigned inp_idx;
    int unsigned prescaler;
    bit          continuous;
    bit          polarity;
    bit [TL_DW-1:0] rd_data;

    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    cnt_idx    = config_params.counter_index;
    inp_idx    = config_params.counter_input;
    prescaler  = config_params.counter_prescaler;
    continuous = config_params.counter_continuous;
    polarity   = config_params.counter_polarity;

    // Settle the selected input away from the edge the counter is looking for, so the first
    // edge of the pattern is the one that opens the measurement.
    drive_pulse(.input_index(inp_idx), .others(config_params.gpio_i),
                .high_cycles(polarity ? 0 : FILTER_CYCLES + 2),
                .low_cycles(polarity ? FILTER_CYCLES + 2 : 0));

    configure_counter(.index(cnt_idx), .continuous(continuous), .polarity(polarity),
                      .input_index(inp_idx), .prescaler(prescaler));

    // Two full periods, so a non-continuous counter completes on the first and a continuous
    // one has a second to measure.
    repeat (2) begin
      drive_pulse(.input_index(inp_idx), .others(config_params.gpio_i),
                  .high_cycles(config_params.counter_high_cycles),
                  .low_cycles(config_params.counter_low_cycles));
    end

    // Let the last period close, including the prescaler cycles the counter needs before it
    // will act on the closing edge.
    drive_pulse(.input_index(inp_idx), .others(config_params.gpio_i),
                .high_cycles(prescaler + 2), .low_cycles(prescaler + 2));

    csr_rd(.ptr(ral.inp_prd_cnt_val[cnt_idx]), .value(rd_data));
    csr_rd(.ptr(ral.inp_prd_cnt_ctrl[cnt_idx]), .value(rd_data));
    disable_counter(cnt_idx);
  end
endtask : main_thread


task ${vseq_name}::configure_counter(int unsigned index, bit continuous, bit polarity,
                                     int unsigned input_index, int unsigned prescaler);
  ral.inp_prd_cnt_ctrl[index].enable.set(1'b1);
  ral.inp_prd_cnt_ctrl[index].continuous_mode.set(continuous);
  ral.inp_prd_cnt_ctrl[index].polarity.set(polarity);
  ral.inp_prd_cnt_ctrl[index].input_select.set(input_index);
  ral.inp_prd_cnt_ctrl[index].prescaler.set(prescaler);
  // csr_wr rather than csr_update: enabling a counter is a side effect, and the mirror may
  // already hold the value the device cleared out from under it.
  csr_wr(.ptr(ral.inp_prd_cnt_ctrl[index]),
         .value(ral.inp_prd_cnt_ctrl[index].get()));
endtask : configure_counter


task ${vseq_name}::disable_counter(int unsigned index);
  csr_wr(.ptr(ral.inp_prd_cnt_ctrl[index]), .value('0));
endtask : disable_counter


task ${vseq_name}::drive_pulse(int unsigned input_index, bit [NUM_GPIOS-1:0] others,
                               int unsigned high_cycles, int unsigned low_cycles);
  bit [NUM_GPIOS-1:0] pu_mask = pullup_mask();
  bit [NUM_GPIOS-1:0] pd_mask = pulldown_mask();
  bit [NUM_GPIOS-1:0] value;

  if (high_cycles > 0) begin
    value = others;
    value[input_index] = 1'b1;
    drive_pins(.value(value), .drive_en('1), .pullup_en(pu_mask), .pulldown_en(pd_mask),
               .hold_cycles(high_cycles));
  end
  if (low_cycles > 0) begin
    value = others;
    value[input_index] = 1'b0;
    drive_pins(.value(value), .drive_en('1), .pullup_en(pu_mask), .pulldown_en(pd_mask),
               .hold_cycles(low_cycles));
  end
endtask : drive_pulse
% endif
