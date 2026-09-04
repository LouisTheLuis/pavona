// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Inherits the reset-safe base so the reset-safe environment gets its clock/reset agent
// configuration and reset domain. The legacy environment continues to work against this same
// object: cip_rst_safe_base_env_cfg extends cip_base_env_cfg and adds to it rather than
// changing anything the legacy path depends on. rv_timer carries the same arrangement.
class gpio_env_cfg extends cip_rst_safe_base_env_cfg #(
  .RAL_T(gpio_reg_block)
);

  // flag to indicate if weak pullup has been introduced on gpio
  // By default, weak pull up is always present
  rand bit pullup_en;
  // flag to indicate if weak pulldown has been introduced on gpio
  rand bit pulldown_en;
  // gpio virtual interface
  gpio_vif gpio_vif;
  // gpio straps interface
  straps_vif straps_vif_inst;
  // Passive observation of the device's hardware register commits. Only the reset-safe
  // environment uses it.
  gpio_probe_vif probe_vif_inst;

  // Build-time elaboration of the device under test, published by the testbench from the
  // same localparams that elaborate the DUT instance. These describe how this build was
  // constructed, not what is happening in it, and nothing may write them after
  // initialize() has run.
  //
  // gpio_async_on: prim_filter_ctr carries a two-flop synchronizer on every input, so an
  // input change reaches data_in two cycles later than it otherwise would.
  // gpio_as_hw_straps_en: the strap sampling logic exists. When it does not,
  // HW_STRAPS_DATA_IN reads zero and sampled_straps_o is tied off.
  bit gpio_async_on;
  bit gpio_as_hw_straps_en;

  // The board has neither weak pull, so a pin nothing is driving is genuinely floating. The
  // legacy path reaches this through +no_pullup_pulldown, and the reset-safe path reads the
  // same plusarg so the two mean the same thing. Set once at initialize() and not randomized:
  // it is a property of the board this run models, not of an operation.
  bit no_pulls;

  // Configuration for the reset-safe GPIO agent. Created here so both environments see the
  // same object, but only the reset-safe environment builds an agent from it.
  gpio_agent_cfg m_gpio_agent_cfg;

  constraint pullup_pulldown_en_c {pullup_en ^ pulldown_en;}

  `uvm_object_utils(gpio_env_cfg)

  function new(string name = "gpio_env_cfg");
    super.new(name);
  endfunction

  virtual function void initialize(bit [TL_AW-1:0] csr_base_addr = '1);
    void'($value$plusargs("no_pullup_pulldown=%0b", no_pulls));
    list_of_alerts = gpio_env_pkg::LIST_OF_ALERTS;
    super.initialize(csr_base_addr);
    // set num_interrupts & num_alerts which will be used to create coverage and more
    num_interrupts = ral.intr_state.get_n_used_bits();

    // only support 1 outstanding TL item
    m_tl_agent_cfg.max_outstanding_req = 1;

    // Used to allow reset operation during a stress all tests and check the CSR after that.
    can_reset_with_csr_accesses = 1'b1;

    // Fatal rather than defaulted: a model that silently assumes an elaboration is the
    // failure this plumbing exists to prevent.
    if (!uvm_config_db#(bit)::get(null, "", "gpio_async_on", gpio_async_on)) begin
      `uvm_fatal(`gfn, "failed to get gpio_async_on from uvm_config_db")
    end
    if (!uvm_config_db#(bit)::get(null, "", "gpio_as_hw_straps_en", gpio_as_hw_straps_en)) begin
      `uvm_fatal(`gfn, "failed to get gpio_as_hw_straps_en from uvm_config_db")
    end
    `uvm_info(`gfn, $sformatf(
              "GPIO elaboration: NumIOs=%0d NumInpPeriodCounters=%0d GpioAsyncOn=%0b GpioAsHwStrapsEn=%0b",
              NUM_GPIOS, NUM_INP_PRD_CNT, gpio_async_on, gpio_as_hw_straps_en), UVM_LOW)


    m_gpio_agent_cfg = gpio_agent_cfg::type_id::create(
        "m_gpio_agent_cfg");
    m_gpio_agent_cfg.if_mode              = dv_utils_pkg::Host;
    m_gpio_agent_cfg.gpio_async_on        = gpio_async_on;
    m_gpio_agent_cfg.gpio_as_hw_straps_en = gpio_as_hw_straps_en;
  endfunction : initialize

endclass
