// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Drives noise at the filter and checks that none of it gets through.
//
// A burst of changes lands inside one filter window, at points that are not aligned to the
// clock, and the pins are returned to the value they started from before the window closes.
// The filter counts consecutive stable samples, so on a pin where it is enabled none of this
// should reach DATA_IN, and on a pin where it is not enabled all of it should.
class gpio_rst_safe_filter_stress_config_parameters
    extends gpio_rst_safe_intr_with_filter_config_parameters;
  `uvm_object_utils(gpio_rst_safe_filter_stress_config_parameters)

  // Changes in one noise burst, and how far into a cycle each one lands. The offset is what
  // makes the change asynchronous to the clock; the driver applies it, so no sequence writes
  // a delay of its own.
  rand int unsigned num_noise_edges;
  rand int unsigned noise_offset_ps;
  rand int unsigned num_noise_bursts;

  // The pins the noise moves. Left unconstrained against the filter enables, so the same
  // burst covers both the pins that should swallow it and the pins that should pass it.
  rand bit [NUM_GPIOS-1:0] noise_mask;

  constraint num_noise_edges_c {
    // Kept below the filter window, so the burst is over before the filter could pass
    // anything even if every edge were counted.
    num_noise_edges inside {[2:FILTER_CYCLES-2]};
  }

  constraint num_noise_bursts_c {
    num_noise_bursts inside {[1:10]};
  }

  // Under one clock period, so an edge lands inside the cycle the driver placed it in rather
  // than in the next one.
  constraint noise_offset_ps_c {
    noise_offset_ps inside {[100:9000]};
  }

  constraint noise_mask_c {
    $countones(noise_mask) > 0;
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : gpio_rst_safe_filter_stress_config_parameters


class gpio_rst_safe_filter_stress_vseq
    extends gpio_rst_safe_intr_with_filter_rand_intr_event_vseq;
  `uvm_object_utils(gpio_rst_safe_filter_stress_vseq)

  extern function new(string name = "");
  extern virtual task main_thread();
  extern protected task drive_noise_burst();
  extern protected task settle_pins();
endclass : gpio_rst_safe_filter_stress_vseq


function gpio_rst_safe_filter_stress_vseq::new(string name = "");
  super.new(name);
  gpio_rst_safe_config_parameters::type_id::set_type_override(
      gpio_rst_safe_filter_stress_config_parameters::get_type());
endfunction : new


task gpio_rst_safe_filter_stress_vseq::main_thread();
  `uvm_info(`gfn, $sformatf("Running %0d operations", test_params.num_trans), UVM_LOW)

  driven_value = '0;

  for (int unsigned i = 0; i < test_params.num_trans; i++) begin
    gpio_rst_safe_filter_stress_config_parameters params;

    `DV_CHECK_RANDOMIZE_FATAL(config_params)
    `downcast(params, config_params)

    csr_wr(.ptr(ral.direct_oe), .value('0));
    csr_wr(.ptr(ral.ctrl_en_input_filter), .value(config_params.filter_enable));
    program_interrupt_registers();

    // Establish the value the noise will be measured against, held long enough that the
    // filter has certainly passed it on every pin.
    settle_pins();
    read_input_and_interrupt_state();

    for (int unsigned burst = 0; burst < params.num_noise_bursts; burst++) begin
      drive_noise_burst();
      // Back to the settled value, and held. On a filtered pin DATA_IN should never have
      // moved; on an unfiltered pin it followed the noise and has now come back.
      settle_pins();
      read_input_and_interrupt_state();
    end

    // Stable changes after the noise, so the operation also covers the filter passing what it
    // is supposed to pass rather than only rejecting what it is not.
    run_pin_schedule();
    read_input_and_interrupt_state();
  end
endtask : main_thread


task gpio_rst_safe_filter_stress_vseq::settle_pins();
  drive_pins(.value(driven_value),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(FILTER_CYCLES + 2));
endtask : settle_pins


task gpio_rst_safe_filter_stress_vseq::drive_noise_burst();
  gpio_rst_safe_filter_stress_config_parameters params;
  bit [NUM_GPIOS-1:0] noisy;
  `downcast(params, config_params)

  noisy = driven_value;

  for (int unsigned edge_num = 0; edge_num < params.num_noise_edges; edge_num++) begin
    noisy ^= params.noise_mask;
    // hold_cycles is zero, so the next edge follows on the next cycle. With the offset applied
    // each edge lands at an unaligned point inside its cycle.
    drive_pins(.value(noisy),
               .drive_en('1),
               .pullup_en(pullup_mask()),
               .pulldown_en(pulldown_mask()),
               .hold_cycles(0),
               .strap_en_pulse(1'b0),
               .drive_offset_ps(params.noise_offset_ps));
  end
endtask : drive_noise_burst
