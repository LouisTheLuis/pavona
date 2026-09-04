// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test-level shape: how many reset epochs, whether reset is applied at all, and how long
// each epoch's workload is. Randomized once and held for the test.
class ${module_instance_name}_rst_safe_test_seq_parameters extends dv_test_seq_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_test_seq_parameters)

  constraint reset_enable_c {
    reset_testing inside {DISABLE, ENABLE};
  }

  constraint reset_loops_c {
    if (reset_testing == ENABLE) num_reset_loops inside {[2:4]};
    else                         num_reset_loops == 1;
  }

  // Operations in one reset epoch. The legacy sequences ran twenty to two hundred in a single
  // pass; this path multiplies a smaller count by the number of reset epochs instead, so that
  // reset lands inside functional work rather than after it. The count is nonetheless kept
  // high enough that stimulus per seed stays within reach of the legacy figure.
  constraint num_trans_c {
    num_trans inside {[8:24]};
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_test_seq_parameters


// Per-operation choices. Randomized inside main_thread(), so each operation in an epoch can
// differ, and re-randomized in a new epoch.
class ${module_instance_name}_rst_safe_config_parameters extends dv_config_parameters;
  `uvm_object_utils(${module_instance_name}_rst_safe_config_parameters)

  // Which pins the testbench drives, and to what. A pin the testbench does not drive is left
  // to the device's output driver or to the weak pull.
  rand bit [NUM_GPIOS-1:0] gpio_i;
  rand bit [NUM_GPIOS-1:0] gpio_i_oe;

  // Board topology. One or the other, never both on a pin, and constant for an epoch.
  rand bit                 use_pullup;

  // Device configuration for this operation.
  rand bit [NUM_GPIOS-1:0] filter_enable;
  rand bit [NUM_GPIOS-1:0] intr_mask;

  // Cycles to hold a pin state. The filter needs FILTER_CYCLES of stability before it will
  // pass a change, so a settle time shorter than that is the interesting case and a longer
  // one is the case where the change must get through.
  rand int unsigned        settle_cycles;

% if num_inp_period_counters > 0:
  // Input period counter stimulus. The pattern is deliberately longer than the filter window
  // on both halves, so a period the counter measures is a period the device's filtered input
  // actually produced rather than one the filter swallowed.
  rand int unsigned counter_index;
  rand int unsigned counter_input;
  rand int unsigned counter_prescaler;
  rand bit          counter_continuous;
  rand bit          counter_polarity;
  rand int unsigned counter_high_cycles;
  rand int unsigned counter_low_cycles;

  constraint counter_c {
    counter_index inside {[0:NUM_INP_PRD_CNT-1]};
    counter_input inside {[0:NUM_GPIOS-1]};
    counter_prescaler inside {[0:3]};
    counter_high_cycles inside {[FILTER_CYCLES+2 : FILTER_CYCLES+12]};
    counter_low_cycles inside {[FILTER_CYCLES+2 : FILTER_CYCLES+12]};
  }
% endif

  // Generic controls the ported operational sequences share. A sequence narrows op_select to
  // the arms it actually has; the legacy sequences chose these with `randcase` and
  // `$urandom_range`, which cannot be replayed from a seed.
  rand int unsigned    op_select;
  rand bit [TL_DW-1:0] csr_value;
  rand bit [5:0]       reg_write_mask;
  rand int unsigned    inter_op_cycles;

  constraint op_select_c {
    op_select inside {[0:3]};
  }

  // The same shape the legacy sequences used for their inter-operation delay.
  constraint inter_op_cycles_c {
    inter_op_cycles dist {0 :/ 20, [1:5] :/ 40, [6:15] :/ 30, [20:25] :/ 10};
  }

  // Delay before reset, in clock/reset agent time steps.
  rand int unsigned        reset_delay;

  constraint gpio_i_oe_c {
    // Drive most pins most of the time. Leaving some undriven exercises the weak pulls,
    // which are the only thing holding the net when the device is not driving either.
    $countones(gpio_i_oe) dist {
      NUM_GPIOS                 :/ 6,
      [NUM_GPIOS/2:NUM_GPIOS-1] :/ 3,
      [0:NUM_GPIOS/2-1]         :/ 1
    };
  }

  constraint filter_enable_c {
    filter_enable dist {'0 :/ 2, '1 :/ 2, [1:'1-1] :/ 6};
  }

  constraint intr_mask_c {
    $countones(intr_mask) > 0;
  }

  constraint settle_cycles_c {
    settle_cycles dist {
      [1:FILTER_CYCLES-1]      :/ 3,
      [FILTER_CYCLES:2*FILTER_CYCLES] :/ 6,
      [2*FILTER_CYCLES+1:200]  :/ 1
    };
  }

  // Clock cycles the reset thread waits before asserting reset, running concurrently with
  // main_thread(). delay_seq counts these with wait_clks(), so the unit is cycles and not
  // simulation time.
  //
  // The bound is the shortest workload an epoch can run, because the reset thread has to
  // finish before main_thread() does and the base class treats the other order as a testbench
  // error. It is deliberately not scaled by the number of operations: a short epoch is one
  // where every operation happened to be fast, so the floor is set by the fastest an
  // operation can be rather than by how many of them there are.
  //
  // The consequence is that reset lands early in a long epoch. The alternative is a delay
  // that sometimes outlives the workload, which produces no reset during functional work at
  // all, so the trade is worth taking. A derived sequence with a longer guaranteed workload
  // can widen this.
  constraint reset_delay_c {
    reset_delay dist {
      [20:60]   :/ 2,
      [61:140]  :/ 5,
      [141:180] :/ 3
    };
  }

  function new(string name = "");
    super.new(name);
  endfunction : new
endclass : ${module_instance_name}_rst_safe_config_parameters


// Reset-safe functional base for ${module_instance_name}.
//
// All pin activity goes through the agent. No sequence derived from this one touches a
// virtual interface, samples a pin or waits on a clock edge; stimulus is items and
// synchronization is monitor transactions.
class ${module_instance_name}_rand_rst_safe_base_vseq extends cip_rand_rst_safe_base_vseq #(
    .RAL_T               (${module_instance_name}_reg_block),
    .CFG_T               (${module_instance_name}_env_cfg),
    .COV_T               (${module_instance_name}_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T (${module_instance_name}_rst_safe_virtual_sequencer),
    .TEST_PARAMS_T       (${module_instance_name}_rst_safe_test_seq_parameters),
    .CONFIG_PARAMS_T     (${module_instance_name}_rst_safe_config_parameters)
  );
  `uvm_object_utils(${module_instance_name}_rand_rst_safe_base_vseq)

  extern function new(string name = "");
  extern virtual task reset_trigger_thread();
  extern virtual task main_thread();
  extern virtual task dut_init();
  extern virtual task post_start();

  // Present a pin state to the device and hold it. Everything a sequence does to the pins
  // goes through here.
  extern virtual task drive_pins(bit [NUM_GPIOS-1:0] value,
                                 bit [NUM_GPIOS-1:0] drive_en,
                                 bit [NUM_GPIOS-1:0] pullup_en,
                                 bit [NUM_GPIOS-1:0] pulldown_en,
                                 int unsigned        hold_cycles = 0,
                                 bit                 strap_en_pulse = 1'b0,
                                 int unsigned        drive_offset_ps = 0);

  // The weak pulls the board provides. Both are empty when the run models a board with none,
  // and every sequence takes its masks from here rather than building them itself, so the
  // board topology is decided in one place.
  extern virtual function bit [NUM_GPIOS-1:0] pullup_mask();
  extern virtual function bit [NUM_GPIOS-1:0] pulldown_mask();

  // Clear the device's output enables, so the testbench is the only thing driving the pins.
  //
  // Every sequence that drives has to do this for itself rather than rely on dut_init(). The
  // stress wrapper turns dut_init() off and runs sequences one after another in a single reset
  // epoch, so a sequence can start with the output enables left set by the one before it, and
  // then both ends drive the same pin.
  extern virtual task release_device_outputs();

  // Wait until the interrupt monitor reports the given pins rising or falling. Reset
  // terminates main_thread() and the virtual sequencer flushes the FIFO, so there is nothing
  // here for a reset to leave behind.
  extern virtual task wait_for_interrupt(bit [NUM_GPIOS-1:0] mask, bit rising = 1'b1);
endclass : ${module_instance_name}_rand_rst_safe_base_vseq


function ${module_instance_name}_rand_rst_safe_base_vseq::new(string name = "");
  super.new(name);
endfunction : new


task ${module_instance_name}_rand_rst_safe_base_vseq::post_start();
  // The common interrupt clearing routine drives CSR traffic outside main_thread(), where
  // the reset-safe base cannot terminate it as a unit. Each sequence clears what it set.
  do_clear_all_interrupts = 1'b0;
  super.post_start();
endtask : post_start


task ${module_instance_name}_rand_rst_safe_base_vseq::reset_trigger_thread();
  delay_seq del_seq;
  reset_seq rst_seq;

  del_seq = delay_seq::type_id::create("del_seq");
  del_seq.delay_time_steps = config_params.reset_delay;
  del_seq.start(p_sequencer.delay_sequencer_h);

  `uvm_info(`gfn, "Triggering reset", UVM_MEDIUM)
  rst_seq = reset_seq::type_id::create("rst_seq");
  rst_seq.start(p_sequencer.clk_rst_sequencer_h);
endtask : reset_trigger_thread


task ${module_instance_name}_rand_rst_safe_base_vseq::main_thread();
  `uvm_fatal(`gfn, "A derived reset-safe sequence must implement main_thread()")
endtask : main_thread


task ${module_instance_name}_rand_rst_safe_base_vseq::dut_init();
  `DV_CHECK_RANDOMIZE_FATAL(config_params)

  // Before anything is driven. Out of reset the device is already driving nothing and this
  // write changes nothing, but the stress wrapper runs this in the middle of a reset epoch,
  // where the device is still driving whatever the previous sequence enabled. Driving the pins
  // first would put the testbench against the device on every pin it had enabled.
  release_device_outputs();

  // Establish the board topology and a known pin state for the epoch. Reset leaves the
  // device driving nothing, so without this the net would float until the first operation.
  drive_pins(.value('0),
             .drive_en('1),
             .pullup_en(pullup_mask()),
             .pulldown_en(pulldown_mask()),
             .hold_cycles(FILTER_CYCLES + 1));

  // Interrupts off and the filter off, so an operation starts from a state it chose rather
  // than one the previous epoch left behind.
  csr_wr(.ptr(ral.intr_enable), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_rising), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_falling), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_lvlhigh), .value('0));
  csr_wr(.ptr(ral.intr_ctrl_en_lvllow), .value('0));
  csr_wr(.ptr(ral.ctrl_en_input_filter), .value('0));
endtask : dut_init


task ${module_instance_name}_rand_rst_safe_base_vseq::drive_pins(
    bit [NUM_GPIOS-1:0] value,
    bit [NUM_GPIOS-1:0] drive_en,
    bit [NUM_GPIOS-1:0] pullup_en,
    bit [NUM_GPIOS-1:0] pulldown_en,
    int unsigned        hold_cycles = 0,
    bit                 strap_en_pulse = 1'b0,
    int unsigned        drive_offset_ps = 0);
  ${module_instance_name}_seq_item item;

  item = ${module_instance_name}_seq_item::type_id::create("item");
  start_item(item, -1, p_sequencer.${module_instance_name}_sequencer_h);
  item.gpio_i          = value;
  item.gpio_i_oe       = drive_en;
  item.pullup_en       = pullup_en;
  item.pulldown_en     = pulldown_en;
  item.hold_cycles     = hold_cycles;
  item.strap_en_pulse  = strap_en_pulse;
  item.drive_offset_ps = drive_offset_ps;
  finish_item(item);
endtask : drive_pins


function bit [NUM_GPIOS-1:0] ${module_instance_name}_rand_rst_safe_base_vseq::pullup_mask();
  if (cfg.no_pulls) return '0;
  return config_params.use_pullup ? '1 : '0;
endfunction : pullup_mask


function bit [NUM_GPIOS-1:0] ${module_instance_name}_rand_rst_safe_base_vseq::pulldown_mask();
  if (cfg.no_pulls) return '0;
  return config_params.use_pullup ? '0 : '1;
endfunction : pulldown_mask


task ${module_instance_name}_rand_rst_safe_base_vseq::release_device_outputs();
  csr_wr(.ptr(ral.direct_oe), .value('0));
endtask : release_device_outputs


task ${module_instance_name}_rand_rst_safe_base_vseq::wait_for_interrupt(
    bit [NUM_GPIOS-1:0] mask, bit rising = 1'b1);
  forever begin
    ${module_instance_name}_intr_item item;

    p_sequencer.intr_event_fifo.get(item);
    if (rising && |(item.rising & mask)) return;
    if (!rising && |(item.falling & mask)) return;
  end
endtask : wait_for_interrupt
