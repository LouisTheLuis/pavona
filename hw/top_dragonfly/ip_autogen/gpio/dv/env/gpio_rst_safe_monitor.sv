// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe monitor for the GPIO pin net and the sampled strap broadcast.
//
// The monitor publishes four different events on four ports. A pin observation says what
// the device can see on its inputs and what this testbench is contributing to that. A strap
// observation says the device latched a strap sample. An interrupt observation says the
// interrupt outputs moved. An input observation says the filtered input the device acts on
// changed. A hardware write observation says the device committed a value into a
// software-visible register. They are separate events with separate consumers, not five
// views of one thing.
//
// All three share one reset lifecycle and one epoch cycle count. That is the reason they live
// in one monitor: the interrupt outputs are a flop of the filtered input state, so a checker
// can only line an interrupt edge up against the pin change that caused it if both
// observations are counted from the same reset boundary by the same counter.
//
// Every publication is a freshly created object. Nothing published is written again.
// REQ_ITEM_T and RSP_ITEM_T are the driver's item type, not the monitor's, because the base
// agent wires the inherited req and rsp ports to the sequencer's FIFOs and those are typed on
// the sequencer's item. This agent has no reactive responder and leaves both ports unused,
// but the types still have to line up for the base class to compile.
class gpio_rst_safe_monitor extends dv_rst_safe_base_monitor #(
    .ITEM_T    (gpio_input_item),
    .REQ_ITEM_T(gpio_seq_item),
    .RSP_ITEM_T(gpio_seq_item),
    .CFG_T     (gpio_agent_cfg),
    .COV_T     (dv_base_agent_cov)
  );
  `uvm_component_utils(gpio_rst_safe_monitor)

  // Strap sample observations.
  uvm_analysis_port #(gpio_straps_item) straps_port;
  // Interrupt output observations.
  uvm_analysis_port #(gpio_intr_item) intr_port;
  // Filtered input observations, taken from inside the device.
  uvm_analysis_port #(gpio_input_item) input_port;
  // Hardware register commits, taken from inside the device.
  uvm_analysis_port #(gpio_hw_write_item) hw_write_port;
  // The device's output drive.
  uvm_analysis_port #(gpio_output_item) output_port;

  // Names the port just written. A consumer reads this in order and takes from the port it
  // names, which is the only thing that makes five typed ports safe to consume.
  uvm_analysis_port #(gpio_probe_kind_e) probe_dir_port;

  // Cycles since the current reset epoch began. Cleared by reset_monitor(), incremented by
  // the cycle counter thread below. Everything it orders is destroyed at reset, so an
  // epoch relative count is the identity a consumer needs.
  protected longint unsigned epoch_cycle;

  // The longest any reset epoch ran. Deliberately not cleared by reset_monitor(), because the
  // question it answers is how long a workload runs, and reset is what ends a workload.
  protected longint unsigned longest_epoch;

  // Last published strap broadcast, used to publish on change.
  protected bit [NUM_GPIOS-1:0] last_straps_data;
  protected bit                 last_straps_valid;

  // Last observed strap request, so the request is published on its edge rather than on every
  // cycle it is held.
  protected bit                 last_strap_en;


  // Last observed interrupt pin state, used to derive edges. Reset clears the device
  // interrupt flops, so the epoch starts from all zeroes and this starts there with it.
  protected bit [NUM_GPIOS-1:0] last_intr_pins;

  // Last observed filtered input, used to derive its edges. Reset clears the device's filter
  // and its input flop, so the epoch starts from all zeroes.
  protected bit [NUM_GPIOS-1:0] last_data_in;
  protected bit [NUM_GPIOS-1:0] last_raw_in;

  // Last observed INTR_STATE content, used to publish on change. Reset clears the register.
  protected bit [NUM_GPIOS-1:0] last_data_out;
  protected bit [NUM_GPIOS-1:0] last_data_oe;

  `uvm_component_new

  extern function void build_phase(uvm_phase phase);
  extern function void report_phase(uvm_phase phase);
  extern virtual task collect_trans();
  extern virtual function void reset_monitor();
  extern protected task collect_probe();
endclass : gpio_rst_safe_monitor


function void gpio_rst_safe_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  straps_port    = new("straps_port", this);
  intr_port      = new("intr_port", this);
  input_port     = new("input_port", this);
  hw_write_port  = new("hw_write_port", this);
  output_port    = new("output_port", this);
  probe_dir_port = new("probe_dir_port", this);
endfunction : build_phase


function void gpio_rst_safe_monitor::report_phase(uvm_phase phase);
  super.report_phase(phase);
  // How many cycles the longest reset epoch ran for. A sequence that applies reset has to do
  // so before its workload finishes, and this is the only place the epoch length is counted.
  `uvm_info(`gfn, $sformatf("longest reset epoch reached %0d cycles", longest_epoch), UVM_LOW)
endfunction : report_phase


task gpio_rst_safe_monitor::collect_trans();
  // One collector for the reset epoch, and one only. Everything the monitor publishes is
  // sampled and written from this single loop, so the order it publishes in is the order a
  // consumer reading probe_dir_port sees. The base class kills this task when reset asserts
  // and restarts it afterwards; nothing here terminates at a protocol boundary.
  collect_probe();
endtask : collect_trans


task gpio_rst_safe_monitor::collect_probe();
  // One pass per clock edge. The cycle counter lives here rather than in a thread of its own
  // so that counting and sampling happen in one process: two processes waking on the same
  // clock event have no defined order between them, and a stamp that can be off by one edge
  // depending on scheduling would be worse than useless to a cycle-based model.
  //
  // The clocking block samples with 1step input skew, so every value read below is the one
  // settled immediately before this edge. epoch_cycle is incremented first, so a stamp of N
  // reads as "sampled just before edge N", that is, the result of edges up to N-1.
  forever begin
    @(cfg.probe_vif_inst.cb);
    epoch_cycle++;
    if (epoch_cycle > longest_epoch) longest_epoch = epoch_cycle;

    // The device's input port is checked at every edge, but the two ways it can be
    // unresolved are not the same fault and are not reported together.
    //
    // An x is the testbench and the device driving one pin to different values. That is
    // always wrong, whatever the board looks like.
    //
    // A z is nobody driving the pin. That is wrong only where something was supposed to be
    // holding it: a driver at either end, or a weak pull. On a board with no pulls a pin
    // nothing drives is genuinely floating, and reporting that would be reporting the board.
    //
    // Either kind reaches DATA_IN and the interrupt logic through the filter, so both are
    // named here at the cycle they happen rather than surfacing later as an unknown on an
    // output.
    begin
      bit [NUM_GPIOS-1:0] held;
      bit [NUM_GPIOS-1:0] contended;
      bit [NUM_GPIOS-1:0] floating;

      held = cfg.gpio_vif.pins_oe[NUM_GPIOS-1:0] |
             cfg.probe_vif_inst.cb.cio_gpio_en_o[NUM_GPIOS-1:0] |
             cfg.gpio_vif.pins_pu[NUM_GPIOS-1:0] |
             cfg.gpio_vif.pins_pd[NUM_GPIOS-1:0];

      contended = '0;
      floating  = '0;
      for (int unsigned i = 0; i < NUM_GPIOS; i++) begin
        if (cfg.probe_vif_inst.cb.cio_gpio_i[i] === 1'bx) contended[i] = 1'b1;
        if (cfg.probe_vif_inst.cb.cio_gpio_i[i] === 1'bz && held[i]) floating[i] = 1'b1;
      end

      if (|contended) begin
        `uvm_error(`gfn, $sformatf({"cio_gpio_i is contended at epoch cycle %0d on pins %0h\n",
                                    "  value: %0b\n",
                                    "  testbench: oe=%0h o=%0h pu=%0h pd=%0h  device: oe=%0h"},
                   epoch_cycle, contended, cfg.probe_vif_inst.cb.cio_gpio_i[NUM_GPIOS-1:0],
                   cfg.gpio_vif.pins_oe, cfg.gpio_vif.pins_o,
                   cfg.gpio_vif.pins_pu, cfg.gpio_vif.pins_pd,
                   cfg.probe_vif_inst.cb.cio_gpio_en_o[NUM_GPIOS-1:0]))
      end
      if (|floating) begin
        `uvm_error(`gfn, $sformatf({"cio_gpio_i is floating at epoch cycle %0d on pins %0h, ",
                                    "which something should have been holding\n",
                                    "  value: %0b\n",
                                    "  testbench: oe=%0h o=%0h pu=%0h pd=%0h  device: oe=%0h"},
                   epoch_cycle, floating, cfg.probe_vif_inst.cb.cio_gpio_i[NUM_GPIOS-1:0],
                   cfg.gpio_vif.pins_oe, cfg.gpio_vif.pins_o,
                   cfg.gpio_vif.pins_pu, cfg.gpio_vif.pins_pd,
                   cfg.probe_vif_inst.cb.cio_gpio_en_o[NUM_GPIOS-1:0]))
      end
    end

    // Publication order inside one pass is deliberate, because a consumer replays these in
    // order against a model it steps one cycle at a time.
    //
    // First, everything that is state entering this cycle: register contents and outputs,
    // which are the result of every earlier cycle and of nothing that happens in this one.
    // A consumer compares those against a model that has not yet stepped this cycle.
    //
    // Then the input observation, which carries this cycle's edges and is what steps the
    // model into this cycle.
    //
    // Last, the combinational write requests, which the device's logic produces while
    // evaluating this cycle and which a consumer can only compare once the model has taken
    // the step.

    // The interrupt outputs, sampled at the same instant as the register that drives them so
    // the one flop between them is a difference of stamps rather than of sampling method.
    if (cfg.probe_vif_inst.cb.intr_gpio_o[NUM_GPIOS-1:0] !== last_intr_pins) begin
      gpio_intr_item item;
      bit [NUM_GPIOS-1:0] pins = cfg.probe_vif_inst.cb.intr_gpio_o[NUM_GPIOS-1:0];

      item = gpio_intr_item::type_id::create("item");
      item.pins        = pins;
      item.rising      = pins & ~last_intr_pins;
      item.falling     = ~pins & last_intr_pins;
      item.epoch_cycle = epoch_cycle;
      last_intr_pins   = pins;
      intr_port.write(item);
      probe_dir_port.write(GpioProbeIntr);
    end

    if (cfg.probe_vif_inst.cb.cio_gpio_o[NUM_GPIOS-1:0] !== last_data_out ||
        cfg.probe_vif_inst.cb.cio_gpio_en_o[NUM_GPIOS-1:0] !== last_data_oe) begin
      gpio_output_item item;

      item = gpio_output_item::type_id::create("item");
      item.data_out    = cfg.probe_vif_inst.cb.cio_gpio_o[NUM_GPIOS-1:0];
      item.data_oe     = cfg.probe_vif_inst.cb.cio_gpio_en_o[NUM_GPIOS-1:0];
      item.epoch_cycle = epoch_cycle;
      last_data_out    = item.data_out;
      last_data_oe     = item.data_oe;
      output_port.write(item);
      probe_dir_port.write(GpioProbeOutput);
    end

    // The strap broadcast, published on change. The device samples straps at most once per
    // reset cycle, so at most one of these carrying valid is expected in an epoch.
    if (cfg.probe_vif_inst.cb.sampled_straps_data[NUM_GPIOS-1:0] !== last_straps_data ||
        cfg.probe_vif_inst.cb.sampled_straps_valid !== last_straps_valid) begin
      gpio_straps_item item;

      item = gpio_straps_item::type_id::create("item");
      item.data        = cfg.probe_vif_inst.cb.sampled_straps_data[NUM_GPIOS-1:0];
      item.valid       = cfg.probe_vif_inst.cb.sampled_straps_valid;
      item.epoch_cycle = epoch_cycle;
      last_straps_data  = item.data;
      last_straps_valid = item.valid;
      straps_port.write(item);
      probe_dir_port.write(GpioProbeStraps);
    end

    // Both ends of the input path, published together on a change of either, so a consumer
    // sees them in a defined order. Published on change; the filter exists to make that rare
    // even when the pins are noisy.
    if (cfg.probe_vif_inst.cb.data_in_d[NUM_GPIOS-1:0] !== last_data_in ||
        cfg.probe_vif_inst.cb.cio_gpio_i[NUM_GPIOS-1:0] !== last_raw_in) begin
      gpio_input_item item;
      bit [NUM_GPIOS-1:0] data_in = cfg.probe_vif_inst.cb.data_in_d[NUM_GPIOS-1:0];
      bit [NUM_GPIOS-1:0] raw_in  = cfg.probe_vif_inst.cb.cio_gpio_i[NUM_GPIOS-1:0];

      item = gpio_input_item::type_id::create("item");
      item.raw_in      = raw_in;
      item.data_in     = data_in;
      item.rising      = data_in & ~last_data_in;
      item.falling     = ~data_in & last_data_in;
      item.epoch_cycle = epoch_cycle;
      last_data_in     = data_in;
      last_raw_in      = raw_in;
      input_port.write(item);
      probe_dir_port.write(GpioProbeInput);
    end

    if (cfg.probe_vif_inst.cb.straps_de) begin
      gpio_hw_write_item item;

      // The data and the valid bit commit on one enable, so they travel as one item.
      item = gpio_hw_write_item::type_id::create("item");
      item.kind        = GpioHwWriteStraps;
      item.value       = cfg.probe_vif_inst.cb.straps_data_d;
      item.aux_valid   = cfg.probe_vif_inst.cb.straps_valid_d;
      item.epoch_cycle = epoch_cycle;
      hw_write_port.write(item);
      probe_dir_port.write(GpioProbeHwWrite);
    end

    // The strap request, published on its rising edge and after the latch above, so that a
    // consumer seeing the request has already seen whatever sample it produced. Reporting the
    // request is what makes a sample the device failed to take visible: without it, a device
    // that ignored the request produces no observation and nothing to check.
    if (cfg.probe_vif_inst.cb.strap_en && !last_strap_en) begin
      gpio_straps_item item;

      item = gpio_straps_item::type_id::create("item");
      item.trigger     = 1'b1;
      // The state the request arrived into. The device samples on `strap_en && !valid`, so a
      // request arriving with valid already set is not meant to produce a second sample.
      item.valid       = last_straps_valid;
      item.data        = last_straps_data;
      item.epoch_cycle = epoch_cycle;
      straps_port.write(item);
      probe_dir_port.write(GpioProbeStraps);
    end
    last_strap_en = cfg.probe_vif_inst.cb.strap_en;

    for (int unsigned i = 0; i < NUM_INP_PRD_CNT; i++) begin
      if (cfg.probe_vif_inst.cb.inp_prd_cnt_val_de[i]) begin
        gpio_hw_write_item item;

        item = gpio_hw_write_item::type_id::create("item");
        item.kind        = GpioHwWriteInpPrdCntVal;
        item.index       = i;
        item.value       = cfg.probe_vif_inst.cb.inp_prd_cnt_val_d[i];
        item.epoch_cycle = epoch_cycle;
        hw_write_port.write(item);
        probe_dir_port.write(GpioProbeHwWrite);
      end
    end
  end
endtask : collect_probe


function void gpio_rst_safe_monitor::reset_monitor();
  // Parser and timing state only. There is no partial publication to discard because every
  // publication here is complete at the instant it is made.
  epoch_cycle       = 0;
  last_straps_data  = '0;
  last_straps_valid = 1'b0;
  last_strap_en     = 1'b0;
  // Reset clears the device interrupt flops, so the next epoch genuinely begins at zero and
  // the first post-reset assertion must publish as a rising edge.
  last_intr_pins    = '0;
  // Reset clears the filter counters and the input flop inside the device, so the filtered
  // input genuinely begins the next epoch at zero.
  last_data_in      = '0;
  last_raw_in       = '0;
  last_data_out     = '0;
  last_data_oe      = '0;
endfunction : reset_monitor
