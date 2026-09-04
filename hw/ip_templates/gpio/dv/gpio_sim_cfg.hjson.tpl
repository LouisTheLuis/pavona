// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
{
  // Name of the sim cfg - typically same as the name of the DUT.
  name: ${module_instance_name}

  // Top level dut name (sv module).
  dut: ${module_instance_name}

  // Top level testbench name (sv module).
  tb: tb

  // Top level variant
  variant: ${topname}

  // Simulator used to sign off this block
  tool: vcs

  // Fusesoc core file used for building the file list.
  fusesoc_core: ${instance_vlnv(f"lowrisc:dv:{module_instance_name}_sim:0.1")}

  // Testplan hjson file.
  testplan: "{self_dir}/../data/${module_instance_name}_testplan.hjson"

  // RAL spec - used to generate the RAL model.
  ral_spec: "{self_dir}/../data/${module_instance_name}.hjson"


  // Import additional common sim cfg files.
  import_cfgs: [// Project wide common sim cfg file
                "{proj_root}/hw/dv/tools/dvsim/common_sim_cfg.hjson",
                // Common CIP test lists
                "{proj_root}/hw/dv/tools/dvsim/tests/csr_tests.hjson",
                "{proj_root}/hw/dv/tools/dvsim/tests/alert_test.hjson",
                "{proj_root}/hw/dv/tools/dvsim/tests/intr_test.hjson",
                "{proj_root}/hw/dv/tools/dvsim/tests/tl_access_tests.hjson",
                "{proj_root}/hw/dv/tools/dvsim/tests/sec_cm_tests.hjson",
                "{proj_root}/hw/dv/tools/dvsim/tests/rst_safe_stress_tests.hjson"]

  // Add additional tops for simulation.
  sim_tops: ["${module_instance_name}_bind", "sec_cm_prim_onehot_check_bind"]

  // Default iterations for all tests - each test entry can override this.
  reseed: 50

  // Default UVM test and seq class name.
  uvm_test: ${module_instance_name}_base_test
  uvm_test_seq: ${module_instance_name}_base_vseq

  // Need to override the default output directory
  overrides: [
    {
      name: scratch_path
      value: "{scratch_base_path}/{name}_{topname}-{flow}-{tool}"
    }
  ]

  // Add GPIO specific exclusion files.
  vcs_cov_excl_files: ["{self_dir}/cov/gpio_cov_excl.el"]

  // List of test specifications.
  tests: [
    {
      name: gpio_smoke
      uvm_test_seq: ${module_instance_name}_smoke_vseq
    }

    {
      name: gpio_smoke_no_pullup_pulldown
      uvm_test_seq: ${module_instance_name}_smoke_vseq
      run_opts: ["+no_pullup_pulldown=1"]
    }

% if num_inp_period_counters > 0:
    {
      name: gpio_inp_prd_cnt
      uvm_test_seq: ${module_instance_name}_inp_prd_cnt_vseq
    }

% endif
    {
      name: gpio_random_dout_din
      uvm_test_seq: ${module_instance_name}_random_dout_din_vseq
    }

    {
      name: gpio_random_dout_din_no_pullup_pulldown
      uvm_test_seq: ${module_instance_name}_random_dout_din_vseq
      run_opts: ["+no_pullup_pulldown=1"]
    }

    {
      name: gpio_dout_din_regs_random_rw
      uvm_test_seq: ${module_instance_name}_dout_din_regs_random_rw_vseq
    }

    {
      name: gpio_intr_rand_pgm
      uvm_test_seq: ${module_instance_name}_intr_rand_pgm_vseq
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_rand_intr_trigger
      uvm_test_seq: ${module_instance_name}_rand_intr_trigger_vseq
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_intr_with_filter_rand_intr_event
      uvm_test_seq: ${module_instance_name}_intr_with_filter_rand_intr_event_vseq
      run_opts: ["+en_scb=0", "+zero_delays=1", "+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_filter_stress
      uvm_test_seq: ${module_instance_name}_filter_stress_vseq
      run_opts: ["+en_scb=0", "+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_random_long_reg_writes_reg_reads
      uvm_test_seq: ${module_instance_name}_random_long_reg_writes_reg_reads_vseq
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_full_random
      uvm_test_seq: ${module_instance_name}_full_random_vseq
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_csr_rw
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_same_csr_outstanding
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_csr_aliasing
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_csr_mem_rw_with_rand_reset
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_tl_intg_err
      run_opts: ["+do_clear_all_interrupts=0"]
    }

    {
      name: gpio_rand_straps
      uvm_test_seq: ${module_instance_name}_rand_straps_vseq
    }

    // Reset-safe path. These run on their own base test and environment; the legacy entries
    // above are untouched and keep their testplan mappings until a reset-safe sequence has
    // been shown to be functionally equivalent.
    {
      name: gpio_rst_safe_smoke
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_smoke_vseq
    }

% if num_inp_period_counters > 0:
    {
      name: gpio_rst_safe_inp_prd_cnt
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_inp_prd_cnt_vseq
    }

% endif
    {
      name: gpio_rst_safe_random_dout_din
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_random_dout_din_vseq
    }

    {
      name: gpio_rst_safe_dout_din_regs_random_rw
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_dout_din_regs_random_rw_vseq
    }

    {
      name: gpio_rst_safe_intr_rand_pgm
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_intr_rand_pgm_vseq
    }

    {
      name: gpio_rst_safe_rand_intr_trigger
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_rand_intr_trigger_vseq
    }

    {
      name: gpio_rst_safe_random_long_reg_writes_reg_reads
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_random_long_reg_writes_reg_reads_vseq
    }

    {
      name: gpio_rst_safe_full_random
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_full_random_vseq
    }

    {
      name: gpio_rst_safe_rand_straps
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_rand_straps_vseq
    }

    {
      name: gpio_rst_safe_intr_with_filter_rand_intr_event
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_intr_with_filter_rand_intr_event_vseq
    }

    {
      name: gpio_rst_safe_filter_stress
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_filter_stress_vseq
    }

    // A board with neither weak pull, so a pin nothing drives is genuinely floating. The
    // legacy path reaches this through the same plusarg.
    {
      name: gpio_rst_safe_smoke_no_pullup_pulldown
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_smoke_vseq
      run_opts: ["+no_pullup_pulldown=1"]
    }

    {
      name: gpio_rst_safe_random_dout_din_no_pullup_pulldown
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_random_dout_din_vseq
      run_opts: ["+no_pullup_pulldown=1"]
    }

    {
      name: gpio_rst_safe_smoke_with_rand_reset
      uvm_test: ${module_instance_name}_rst_safe_base_test
      uvm_test_seq: ${module_instance_name}_rst_safe_smoke_with_rand_reset_vseq
    }
  ]

  // List of regressions.
  regressions: [
    {
      name: smoke
      tests: ["gpio_smoke", "gpio_rst_safe_smoke"]
    }
  ]
}
