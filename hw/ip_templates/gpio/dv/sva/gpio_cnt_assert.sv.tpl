// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The part of the input period counter contract that the counter itself owns: when a
// measurement completes it publishes the value, and in non-continuous mode it turns itself off.
//
// The measured value is checked in the scoreboard, which counts the cycles between the edges
// the counter selected. What is checked here is the accompanying register behavior, which is a
// single cycle relationship and belongs where the signals are.
module ${module_instance_name}_cnt_assert
#(
  parameter int unsigned NumCounters = 8
) (
  input logic          clk_i,
  input logic          rst_ni,
  input ${module_instance_name}_reg_pkg::${module_instance_name}_reg2hw_t reg2hw,
  input ${module_instance_name}_reg_pkg::${module_instance_name}_hw2reg_t hw2reg
);

  for (genvar i = 0; i < NumCounters; i++) begin : gen_cnt_assert
    // A completed measurement in non-continuous mode turns the counter off, in the same cycle
    // it publishes the value.
    `ASSERT(CntSelfClears_A,
            hw2reg.inp_prd_cnt_val[i].de && !reg2hw.inp_prd_cnt_ctrl[i].continuous_mode.q
            |-> hw2reg.inp_prd_cnt_ctrl[i].enable.de && !hw2reg.inp_prd_cnt_ctrl[i].enable.d,
            clk_i, !rst_ni)

    // In continuous mode it keeps running, which is the whole difference between the modes.
    `ASSERT(CntKeepsRunningContinuous_A,
            hw2reg.inp_prd_cnt_val[i].de && reg2hw.inp_prd_cnt_ctrl[i].continuous_mode.q
            |-> !hw2reg.inp_prd_cnt_ctrl[i].enable.de,
            clk_i, !rst_ni)

    // The counter never writes its own enable for any other reason. Without this the two above
    // would pass on a counter that disabled itself whenever it felt like it.
    `ASSERT(CntEnableOnlyOnCommit_A,
            hw2reg.inp_prd_cnt_ctrl[i].enable.de |-> hw2reg.inp_prd_cnt_val[i].de,
            clk_i, !rst_ni)
  end : gen_cnt_assert

endmodule
