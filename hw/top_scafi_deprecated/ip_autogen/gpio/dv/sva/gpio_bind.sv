// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module gpio_bind;

  bind gpio tlul_assert #(
    .EndpointType("Device")
  ) tlul_assert_device (
    .clk_i,
    .rst_ni,
    .h2d  (tl_i),
    .d2h  (tl_o)
  );

  bind gpio gpio_csr_assert_fpv gpio_csr_assert (
    .clk_i,
    .rst_ni,
    .h2d    (tl_i),
    .d2h    (tl_o)
  );

  bind gpio gpio_intr_assert #(
    .NumIOs(NumIOs)
  ) gpio_intr_assert (
    .clk_i,
    .rst_ni,
    .data_in        (data_in_d),
    .intr_state     (reg2hw.intr_state.q),
    .intr_enable    (reg2hw.intr_enable.q),
    .en_rising      (reg2hw.intr_ctrl_en_rising.q),
    .en_falling     (reg2hw.intr_ctrl_en_falling.q),
    .en_lvlhigh     (reg2hw.intr_ctrl_en_lvlhigh.q),
    .en_lvllow      (reg2hw.intr_ctrl_en_lvllow.q),
    .intr_state_we  (u_reg.intr_state_we),
    .intr_state_wd  (u_reg.intr_state_wd[NumIOs-1:0]),
    .intr_test_qe   (reg2hw.intr_test.qe),
    .intr_test_q    (reg2hw.intr_test.q),
    .intr_o         (intr_gpio_o)
  );

  // Bound to the block, not to prim_filter_ctr. The primitive's internals are not this
  // block's to depend on, and binding by module name would also attach the property to every
  // instance of that primitive in whatever design this file is elaborated into.
  bind gpio gpio_filter_assert #(
    .NumIOs(NumIOs)
  ) gpio_filter_assert (
    .clk_i,
    .rst_ni,
    .raw_in    (cio_gpio_i),
    .filter_en (reg2hw.ctrl_en_input_filter.q),
    .data_in   (data_in_d)
  );


endmodule
