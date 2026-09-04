// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe environment.
//
// It is a separate environment from ${module_instance_name}_env rather than a modification of it, so the
// legacy path keeps working while this one is developed. Only one of the two is built in any
// given test, so the two never contend for the pin interfaces.
class ${module_instance_name}_rst_safe_env extends cip_rst_safe_base_env #(
    .CFG_T               (${module_instance_name}_env_cfg),
    .COV_T               (${module_instance_name}_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T (${module_instance_name}_rst_safe_virtual_sequencer),
    .SCOREBOARD_T        (${module_instance_name}_rst_safe_scoreboard)
  );
  `uvm_component_utils(${module_instance_name}_rst_safe_env)

  ${module_instance_name}_rst_safe_agent m_${module_instance_name}_agent;

  extern function new(string name = "", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass : ${module_instance_name}_rst_safe_env


function ${module_instance_name}_rst_safe_env::new(string name = "", uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void ${module_instance_name}_rst_safe_env::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // The pin interfaces. The common base has already retrieved intr_vif into cfg, so the
  // agent takes its handle from there rather than fetching it a second time and risking a
  // different one.
  if (!uvm_config_db#(gpio_vif)::get(this, "", "gpio_vif", cfg.gpio_vif)) begin
    `uvm_fatal(`gfn, "failed to get gpio_vif from uvm_config_db")
  end
  if (!uvm_config_db#(straps_vif)::get(this, "", "straps_vif", cfg.straps_vif_inst)) begin
    `uvm_fatal(`gfn, "failed to get straps_vif from uvm_config_db")
  end
  if (!uvm_config_db#(${module_instance_name}_probe_vif)::get(this, "", "probe_vif",
                                                              cfg.probe_vif_inst)) begin
    `uvm_fatal(`gfn, "failed to get probe_vif from uvm_config_db")
  end

  m_${module_instance_name}_agent = ${module_instance_name}_rst_safe_agent::type_id::create(
      "m_${module_instance_name}_agent", this);
  uvm_config_db#(${module_instance_name}_agent_cfg)::set(
      this, "m_${module_instance_name}_agent*", "cfg", cfg.m_${module_instance_name}_agent_cfg);

  cfg.m_${module_instance_name}_agent_cfg.gpio_vif        = cfg.gpio_vif;
  cfg.m_${module_instance_name}_agent_cfg.straps_vif_inst = cfg.straps_vif_inst;
  cfg.m_${module_instance_name}_agent_cfg.intr_vif_inst   = cfg.intr_vif;
  cfg.m_${module_instance_name}_agent_cfg.probe_vif_inst  = cfg.probe_vif_inst;
  cfg.m_${module_instance_name}_agent_cfg.en_cov          = cfg.en_cov;
  // One reset domain in this block. The common base owns the domain object.
  cfg.m_${module_instance_name}_agent_cfg.reset_domain    = cfg.reset_domain;

  // Board topology, taken from the environment configuration's one-time randomization so the
  // reset-safe path keeps the legacy choice between a pulled-up and a pulled-down board.
  // What the driver restores at reset. On a board with no pulls there is nothing to restore,
  // and a pin nothing drives is then genuinely floating rather than held.
  cfg.m_${module_instance_name}_agent_cfg.default_pullup_en =
      cfg.no_pulls ? '0 : {NUM_GPIOS{cfg.pullup_en}};
  cfg.m_${module_instance_name}_agent_cfg.default_pulldown_en =
      cfg.no_pulls ? '0 : {NUM_GPIOS{cfg.pulldown_en}};
endfunction : build_phase


function void ${module_instance_name}_rst_safe_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  virtual_sequencer.${module_instance_name}_sequencer_h = m_${module_instance_name}_agent.sequencer;

  // Stimulus side. These are the observations a sequence may need in order to wait for
  // something the device did.
  m_${module_instance_name}_agent.monitor.intr_port.connect(
      virtual_sequencer.intr_event_fifo.analysis_export);
  m_${module_instance_name}_agent.monitor.straps_port.connect(
      virtual_sequencer.straps_event_fifo.analysis_export);

  if (cfg.en_scb) begin
    // Checking side. Independent exports from the same ports, so the scoreboard receives
    // every observation whether or not a sequence is also consuming one.
    m_${module_instance_name}_agent.monitor.intr_port.connect(
        scoreboard.intr_event_fifo.analysis_export);
    m_${module_instance_name}_agent.monitor.straps_port.connect(
        scoreboard.straps_event_fifo.analysis_export);
    m_${module_instance_name}_agent.monitor.input_port.connect(
        scoreboard.input_state_fifo.analysis_export);
    m_${module_instance_name}_agent.monitor.hw_write_port.connect(
        scoreboard.hw_write_fifo.analysis_export);
    m_${module_instance_name}_agent.monitor.output_port.connect(
        scoreboard.output_fifo.analysis_export);
    // Connected last, and consumed first: this is what puts the five above into order.
    m_${module_instance_name}_agent.monitor.probe_dir_port.connect(
        scoreboard.probe_dir_fifo.analysis_export);
  end
endfunction : connect_phase
