// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Publishes interrupt-pin edges without using a clocking interface. The event
// control waits for the next pin change; sampling and publication are zero-time.
class csrng_intr_monitor extends uvm_component;
  `uvm_component_utils(csrng_intr_monitor)

  intr_vif vif;
  uvm_analysis_port #(csrng_intr_item) analysis_port;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_port = new("analysis_port", this);
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    bit [NumCsrngIntr-1:0] previous_pins;

    previous_pins = vif.pins[NumCsrngIntr-1:0];
    forever begin
      csrng_intr_item item;
      bit [NumCsrngIntr-1:0] pins;

      @(vif.pins);
      pins = vif.pins[NumCsrngIntr-1:0];
      `uvm_create_obj(csrng_intr_item, item)
      item.pins = pins;
      item.rising = pins & ~previous_pins;
      item.falling = ~pins & previous_pins;
      previous_pins = pins;
      analysis_port.write(item);
    end
  endtask : run_phase
endclass : csrng_intr_monitor
