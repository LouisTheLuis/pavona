// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Passive observation of the device's hardware-written register commits, bound into the
// top level of gpio.
//
// These registers are written by hardware rather than over the bus, so their values cannot
// be reconstructed from bus traffic. Each observation therefore has to carry the hardware
// update enable and the complete committed value; the monitor adds the cycle count that
// orders it against everything else.
//
// This interface only reads. It never drives, forces or releases anything.
interface gpio_probe_if ();

  import gpio_reg_pkg::*;

  // Upward name references into the enclosing device, in the manner of rom_ctrl_if.
  logic clk;
  logic rst_n;
  assign clk   = dut.clk_i;
  assign rst_n = dut.rst_ni;

  // The input the device sees on its port. Sampled by the same clocking block as everything
  // else below, so the raw input and its filtered result are read at one instant and no
  // scheduling order between two processes can put them out of step. The bidirectional net is
  // also observable from pins_if, but only asynchronously, which is the wrong thing to drive a
  // cycle-based model with.
  logic [NumIOs-1:0] cio_gpio_i;
  assign cio_gpio_i = dut.cio_gpio_i;

  // The device's output drive. Sampled rather than resolved from the net, because the net is
  // the combination of what the device drives, what the testbench drives and the board's
  // pulls, and comparing a prediction of one contributor against the resolved sum of three
  // means guessing which of them moved. These two are the architectural output.
  logic [NumIOs-1:0] cio_gpio_o;
  logic [NumIOs-1:0] cio_gpio_en_o;
  assign cio_gpio_o    = dut.cio_gpio_o;
  assign cio_gpio_en_o = dut.cio_gpio_en_o;

  // The sampled strap broadcast, read here rather than watched on the strap interface, so
  // that it is taken at the same instant as everything else and lands in the same ordered
  // account.
  logic [NumIOs-1:0] sampled_straps_data;
  logic              sampled_straps_valid;
  assign sampled_straps_data  = dut.sampled_straps_o.data;
  assign sampled_straps_valid = dut.sampled_straps_o.valid;

  // The interrupt outputs, sampled here rather than watched asynchronously on the shared
  // interrupt interface. The interrupt is one flop behind INTR_STATE, so checking it means
  // relating two observations one cycle apart; that only works if both are taken at the same
  // instant in the same way. An asynchronous watcher sees the pin after the non-blocking
  // update and would stamp it an edge earlier than the clocked view of the register.
  logic [NumIOs-1:0] intr_gpio_o;
  assign intr_gpio_o = dut.intr_gpio_o;

  // The threshold prim_filter_ctr is instantiated with. The model derives its window from
  // FILTER_CYCLES, and the scoreboard compares the two once at start of simulation so that a
  // change of CntWidth in the design cannot leave the model quietly filtering for a
  // different number of cycles than the device.
  logic [3:0] filter_thresh;
  assign filter_thresh = dut.gen_filter[0].u_filter.thresh_i;

  // The GPIO input after the optional two-flop synchronizer and the noise filter. Everything
  // software can see derives from this: DATA_IN copies it, interrupt events are its edges,
  // and the strap sample is a snapshot of it. Observing it means the testbench does not have
  // to reproduce the synchronizer and filter latency in order to predict anything
  // downstream, which is what makes the model independent of GpioAsyncOn.
  logic [NumIOs-1:0] data_in_d;
  assign data_in_d = dut.data_in_d;

  // INTR_STATE content. Observed as the stored register value rather than as the hardware
  // write request, for two reasons.
  //
  // Rate: prim_intr_hw asserts de on every cycle a level-triggered condition holds, so the
  // write request is continuous while a level interrupt is active and would produce an
  // observation per clock. The stored value moves once and then stays.
  //
  // Correctness: prim_subreg_arb resolves a software write against a hardware write in the
  // same cycle, for W1C as `wr_data = (de ? d : q) & (we ? ~wd : '1)`, so software wins on a
  // collision. The stored value is the outcome of that arbitration; the write request is only

  // The strap latch. Both registers commit on the same enable, so the data and the valid bit
  // are one event and have to be observed together.
  logic                straps_de;
  logic [NumIOs-1:0]   straps_data_d;
  logic                straps_valid_d;
  // The request the latch above answers. Without it a sample the device never took looks the
  // same as no request having been made, because both produce no observation at all.
  logic                strap_en;
  assign strap_en       = dut.strap_en_i;

  assign straps_de      = dut.hw2reg.hw_straps_data_in.de;
  assign straps_data_d  = dut.hw2reg.hw_straps_data_in.d;
  assign straps_valid_d = dut.hw2reg.hw_straps_data_in_valid.d;

  // Input period counters. Two separate hardware writes per counter: the measured value,
  // and the self-clear of the enable bit that ends a non-continuous measurement.
  logic [NumInpPeriodCounters-1:0]        inp_prd_cnt_val_de;
  logic [NumInpPeriodCounters-1:0][31:0]  inp_prd_cnt_val_d;

  // Every signal above is combinational input to a register flop, so it changes on the same
  // edge that commits it. The 1step input skew samples the settled pre-edge value and takes
  // the race out of the observation.
  clocking cb @(posedge clk);
    default input #1step;
    input cio_gpio_i;
    input data_in_d;
    input intr_gpio_o;
    input cio_gpio_o, cio_gpio_en_o;
    input sampled_straps_data, sampled_straps_valid;
    input straps_de, straps_data_d, straps_valid_d;
    input strap_en;
    input inp_prd_cnt_val_de, inp_prd_cnt_val_d;
  endclocking

endinterface : gpio_probe_if
