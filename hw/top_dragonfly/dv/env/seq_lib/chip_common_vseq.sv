// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_common_vseq extends chip_stub_cpu_base_vseq;
  `uvm_object_utils(chip_common_vseq)

  constraint num_trans_c {
    num_trans inside {[1:2]};
  }
  `uvm_object_new

  virtual task post_apply_reset(string reset_kind = "HARD");
    super.post_apply_reset(reset_kind);

    for (int ram_idx = 0; ram_idx < cfg.num_ram_ret_tiles; ram_idx++) begin
      cfg.mem_bkdr_util_h[chip_mem_e'(RamRet0 + ram_idx)].randomize_mem();
    end
    for (int ram_idx = 0; ram_idx < cfg.num_ram_main_tiles; ram_idx++) begin
      cfg.mem_bkdr_util_h[chip_mem_e'(RamMain0 + ram_idx)].randomize_mem();
    end
    for (int ram_idx = 0; ram_idx < cfg.num_ram_ctn_tiles; ram_idx++) begin
      cfg.mem_bkdr_util_h[chip_mem_e'(RamCtn0 + ram_idx)].randomize_mem();
    end
  endtask

  virtual task body();
    string csr_test_type;
    void'($value$plusargs("+csr_%0s", csr_test_type));
    // sio are driven X when csb is inactive, but these pins can be configured as wakeup cause,
    // assign a known value to avoid X propagation in case that `PINMUX.WKUP_CAUSE` is programmed.
    cfg.chip_vif.spi_host_if.sio_out = $urandom;

    // These types of CSR tests are quite long; run them only once.
    if (csr_test_type inside {"bit_bash", "aliasing"}) num_trans = 1;
    run_common_vseq_wrapper(num_trans);
  endtask : body

  virtual function void apply_chip_csr_exclusions();
    csr_excl_item csr_excl;

    if (cfg.ral_models.exists("chip_reg_block")) begin
      csr_excl = cfg.ral_models["chip_reg_block"].get_excl_item();
      `DV_CHECK_NE_FATAL(csr_excl, null)

      // These trace CSRs are driven by soc_dbg_ctrl hardware policy state. Chip-level init and
      // generic CSR tests can legitimately observe values different from the static RAL reset.
      csr_excl.add_excl("chip_reg_block.soc_dbg_ctrl_core.trace_debug_policy_category",
                        CsrExclCheck, CsrAllTests);
      csr_excl.add_excl("chip_reg_block.soc_dbg_ctrl_core.trace_debug_policy_valid_relocked",
                        CsrExclCheck, CsrAllTests);

      // GPIO direct output/OE CSRs are hwext/hrw and connected to live chip IO state. Random
      // chip-level CSR writes can make their readback differ from the RAL mirror and can also
      // affect pad drive behavior, so skip them in non-init CSR stress tests.
      csr_excl.add_excl("chip_reg_block.gpio.direct_out", CsrExclAll, CsrNonInitTests);
      csr_excl.add_excl("chip_reg_block.gpio.direct_oe", CsrExclAll, CsrNonInitTests);

      // GPIO input period counters observe live GPIO inputs. Their control registers contain
      // fields that hardware can clear or reject while a measurement is active, and their value
      // registers are hardware-written read-clear CSRs. Generic outstanding CSR traffic cannot
      // rely on stable RAL mirror readback for these registers.
      for (int i = 0; i < 8; i++) begin
        csr_excl.add_excl($sformatf("chip_reg_block.gpio.inp_prd_cnt_ctrl_%0d", i),
                          CsrExclAll, CsrNonInitTests);
        csr_excl.add_excl($sformatf("chip_reg_block.gpio.inp_prd_cnt_val_%0d", i),
                          CsrExclAll, CsrNonInitTests);
      end
    end

    if (cfg.ral_models.exists("chip_soc_dbg_reg_block")) begin
      csr_excl = cfg.ral_models["chip_soc_dbg_reg_block"].get_excl_item();
      `DV_CHECK_NE_FATAL(csr_excl, null)

      csr_excl.add_excl(
          "chip_soc_dbg_reg_block.soc_dbg_ctrl_jtag.jtag_trace_debug_policy_category",
          CsrExclCheck, CsrAllTests);
      csr_excl.add_excl(
          "chip_soc_dbg_reg_block.soc_dbg_ctrl_jtag.jtag_trace_debug_policy_valid_relocked",
          CsrExclCheck, CsrAllTests);
      csr_excl.add_excl("chip_soc_dbg_reg_block.soc_dbg_ctrl_jtag.jtag_boot_status",
                        CsrExclCheck, CsrAllTests);
    end

    apply_racl_policy_csr_exclusions("chip_reg_block");
    apply_racl_policy_csr_exclusions("chip_soc_mbx_reg_block");
  endfunction

  virtual function void apply_racl_policy_csr_exclusions(string ral_model_name);
    csr_excl_item csr_excl;
    string prefix;

    if (!cfg.ral_models.exists(ral_model_name)) return;

    csr_excl = cfg.ral_models[ral_model_name].get_excl_item();
    `DV_CHECK_NE_FATAL(csr_excl, null)

    prefix = {ral_model_name, "."};

    // These registers define RACL policy for later TL accesses. Random generic CSR writes can
    // intentionally revoke permissions, making subsequent accesses return TL d_error.
    csr_excl.add_excl({prefix, "racl_ctrl.policy_all_rd_wr_shadowed"},
                      CsrExclWrite, CsrAllTests);
    csr_excl.add_excl({prefix, "racl_ctrl.policy_rot_private_shadowed"},
                      CsrExclWrite, CsrAllTests);
    csr_excl.add_excl({prefix, "racl_ctrl.policy_soc_rot_shadowed"},
                      CsrExclWrite, CsrAllTests);

    for (int i = 0; i < 32; i++) begin
      csr_excl.add_excl($sformatf("%0sac_range_check.range_racl_policy_shadowed_%0d",
                                  prefix, i),
                        CsrExclWrite, CsrAllTests);
    end
  endfunction

  virtual task pre_start();
    // CSR tests write to chip CSRs, which includes the pinmux registers. Random writes to the
    // pinmux may inadvertently connect the chip IOs to peripherals, causing Xs to propagate, if
    // the chip MIOs are not initialized. Hence, we weakly pull down ALL MIOs for these tests.
    cfg.chip_vif.mios_if.pins_pd = '1;
    cfg.chip_vif.dios_if.pins_pd[top_dragonfly_pkg::DioPadSpiDevD3:
                                 top_dragonfly_pkg::DioPadSpiHostD0] = '1;

    // Automated csr tests will cover the chip_soc_mbx_ral, so connect it
    cfg.chip_vif.connect_mbx_if();

    apply_chip_csr_exclusions();

    super.pre_start();
  endtask

  virtual task post_start();
    super.post_start();
    cfg.chip_vif.mios_if.pins_pd = '0;
    cfg.chip_vif.dios_if.pins_pd[top_dragonfly_pkg::DioPadSpiDevD3:
                                 top_dragonfly_pkg::DioPadSpiHostD0] = '0;
  endtask

endclass
