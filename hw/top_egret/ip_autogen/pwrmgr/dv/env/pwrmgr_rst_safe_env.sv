// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The reset-safe environment for the power manager.
//
// It owns the two block agents and settles which reset each part of the testbench recovers on. The
// device receives four resets and only one is stimulus.
//
// The shared escalation agent is not created here: its sender driver can only hold the pair at
// idle, and the fast agent owns that interface instead. Dropping the agent drops its monitor, so
// the observation path the escalation checking needs has to be built when that modelling lands.
class pwrmgr_rst_safe_env extends cip_rst_safe_base_env #(
    .CFG_T              (pwrmgr_env_cfg),
    .COV_T              (pwrmgr_rst_safe_env_cov),
    .VIRTUAL_SEQUENCER_T(pwrmgr_rst_safe_virtual_sequencer),
    .SCOREBOARD_T       (pwrmgr_rst_safe_scoreboard)
  );

  `uvm_component_utils(pwrmgr_rst_safe_env)
  `uvm_component_new

  pwrmgr_aon_rst_safe_agent  m_aon_agent;
  pwrmgr_fast_rst_safe_agent m_fast_agent;

  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);

  extern protected function void get_interfaces();
  extern protected function void build_reset_domains();
  extern protected function void build_block_agents();
endclass : pwrmgr_rst_safe_env


function void pwrmgr_rst_safe_env::build_phase(uvm_phase phase);
  super.build_phase(phase);

  get_interfaces();
  build_reset_domains();
  build_block_agents();

  // The always-on clock runs at the ratio this top builds pwrmgr with. The period is taken from the
  // bus clock rather than set absolutely, so the ratio holds whatever the bus clock randomized to.
  cfg.slow_clk_rst_vif.set_period_ps(cfg.clk_rst_vif.clk_period_ps * BusCyclesPerAonCycle);
  cfg.esc_clk_rst_vif.set_freq_mhz(cfg.clk_rst_vif.clk_freq_mhz);
  cfg.lc_clk_rst_vif.set_freq_mhz(cfg.clk_rst_vif.clk_freq_mhz);
endfunction : build_phase


function void pwrmgr_rst_safe_env::get_interfaces();
  if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "slow_clk_rst_vif",
                                               cfg.slow_clk_rst_vif)) begin
    `uvm_fatal(`gfn, "failed to get slow_clk_rst_vif from uvm_config_db")
  end
  if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "esc_clk_rst_vif",
                                               cfg.esc_clk_rst_vif)) begin
    `uvm_fatal(`gfn, "failed to get esc_clk_rst_vif from uvm_config_db")
  end
  if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "lc_clk_rst_vif",
                                               cfg.lc_clk_rst_vif)) begin
    `uvm_fatal(`gfn, "failed to get lc_clk_rst_vif from uvm_config_db")
  end
  if (!uvm_config_db#(virtual pwrmgr_if)::get(this, "", "pwrmgr_vif", cfg.pwrmgr_vif)) begin
    `uvm_fatal(`gfn, "failed to get pwrmgr_vif from uvm_config_db")
  end
  // Published for the escalation agent this environment does not create, so it is fetched
  // under the name the testbench publishes it with.
  if (!uvm_config_db#(virtual alert_esc_if)::get(this, "m_esc_agent", "vif",
                                                 cfg.m_esc_agent_cfg.vif)) begin
    `uvm_fatal(`gfn, "failed to get the escalation interface from uvm_config_db")
  end

  // Needed so a test that deliberately wedges the device can stand down the two checks that
  // require a reset request to be forwarded, which a wedged device cannot do.
  if (!uvm_config_db#(virtual pwrmgr_rstreqs_sva_if)::get(
          this, "", "pwrmgr_rstreqs_sva_vif", cfg.pwrmgr_rstreqs_sva_vif
      )) begin
    `uvm_fatal(`gfn, "failed to get pwrmgr_rstreqs_sva_vif from uvm_config_db")
  end

  // The interface drives the sender side only when told that is the role it plays, and the agent
  // that normally tells it is not created here. Without this the pair stays high impedance.
  cfg.m_esc_agent_cfg.vif.is_alert  = 1'b0;
  cfg.m_esc_agent_cfg.vif.is_active = 1'b1;
  cfg.m_esc_agent_cfg.vif.if_mode   = dv_utils_pkg::Host;
endfunction : get_interfaces


// The power-on reset is the only reset a test applies, and it is the always-on one. The base built
// the primary domain from the register block's clock, the fast interface, so it is replaced here.
// The three resets the device produces get domains that can be waited on but never applied.
function void pwrmgr_rst_safe_env::build_reset_domains();
  dv_rst_domain por_domain;

  // The power-on reset applies to the always-on interface and nothing else. The three resets
  // that fall with it are asserted by the always-on driver, which is the component that owns
  // those interfaces.
  por_domain = dv_rst_domain::type_id::create("por_domain");
  por_domain.clk_rst_vif = cfg.slow_clk_rst_vif;

  cfg.reset_domain = por_domain;
  // The base assigned the clock/reset agent the domain it built. Point the agent at the one
  // that is actually the power-on reset, or it would drive the fast interface instead.
  cfg.clk_rst_agt_cfg.reset_domain = cfg.reset_domain;

  cfg.fast_reset_domain = pwrmgr_derived_rst_domain::type_id::create("fast_reset_domain");
  cfg.fast_reset_domain.clk_rst_vif = cfg.clk_rst_vif;

  cfg.lc_reset_domain = pwrmgr_derived_rst_domain::type_id::create("lc_reset_domain");
  cfg.lc_reset_domain.clk_rst_vif = cfg.lc_clk_rst_vif;

  cfg.esc_reset_domain = pwrmgr_derived_rst_domain::type_id::create("esc_reset_domain");
  cfg.esc_reset_domain.clk_rst_vif = cfg.esc_clk_rst_vif;

  // The bus runs on the fast clock, so it recovers on the fast domain's reset rather than on
  // the power-on reset. It is assigned here rather than left to the inherited path because
  // that path hands every bus agent the primary domain.
  foreach (cfg.m_tl_agent_cfgs[i]) begin
    cfg.m_tl_agent_cfgs[i].reset_domain = cfg.fast_reset_domain;
  end
endfunction : build_reset_domains


function void pwrmgr_rst_safe_env::build_block_agents();
  cfg.m_aon_agent_cfg = pwrmgr_aon_agent_cfg::type_id::create("m_aon_agent_cfg");
  `DV_CHECK_RANDOMIZE_FATAL(cfg.m_aon_agent_cfg)
  cfg.m_aon_agent_cfg.vif               = cfg.pwrmgr_vif;
  cfg.m_aon_agent_cfg.fast_clk_rst_vif  = cfg.clk_rst_vif;
  cfg.m_aon_agent_cfg.lc_clk_rst_vif    = cfg.lc_clk_rst_vif;
  cfg.m_aon_agent_cfg.esc_clk_rst_vif   = cfg.esc_clk_rst_vif;
  cfg.m_aon_agent_cfg.esc_vif           = cfg.m_esc_agent_cfg.vif;
  cfg.m_aon_agent_cfg.en_cov            = cfg.en_cov;
  // Alive across every reset it has to restore for the other domains.
  cfg.m_aon_agent_cfg.reset_domain      = cfg.reset_domain;

  cfg.m_fast_agent_cfg = pwrmgr_fast_agent_cfg::type_id::create("m_fast_agent_cfg");
  `DV_CHECK_RANDOMIZE_FATAL(cfg.m_fast_agent_cfg)
  cfg.m_fast_agent_cfg.vif              = cfg.pwrmgr_vif;
  cfg.m_fast_agent_cfg.lc_clk_rst_vif   = cfg.lc_clk_rst_vif;
  cfg.m_fast_agent_cfg.esc_clk_rst_vif  = cfg.esc_clk_rst_vif;
  cfg.m_fast_agent_cfg.esc_vif          = cfg.m_esc_agent_cfg.vif;
  cfg.m_fast_agent_cfg.en_cov           = cfg.en_cov;
  // Not the lc reset: this agent grants that one, and nothing can be reset by what it drives.
  cfg.m_fast_agent_cfg.reset_domain     = cfg.fast_reset_domain;

  m_aon_agent = pwrmgr_aon_rst_safe_agent::type_id::create("m_aon_agent", this);
  uvm_config_db#(pwrmgr_aon_agent_cfg)::set(this, "m_aon_agent*", "cfg", cfg.m_aon_agent_cfg);

  m_fast_agent = pwrmgr_fast_rst_safe_agent::type_id::create("m_fast_agent", this);
  uvm_config_db#(pwrmgr_fast_agent_cfg)::set(this, "m_fast_agent*", "cfg", cfg.m_fast_agent_cfg);

endfunction : build_block_agents


function void pwrmgr_rst_safe_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  m_aon_agent.monitor.aon_dir_port.connect(scoreboard.aon_dir_fifo.analysis_export);
  m_fast_agent.monitor.fast_dir_port.connect(scoreboard.fast_dir_fifo.analysis_export);
  m_aon_agent.monitor.clk_valid_port.connect(scoreboard.clk_valid_fifo.analysis_export);
  m_aon_agent.monitor.glitch_port.connect(scoreboard.glitch_fifo.analysis_export);
  m_fast_agent.monitor.esc_timeout_port.connect(scoreboard.esc_timeout_fifo.analysis_export);
  m_aon_agent.monitor.wakeup_port.connect(scoreboard.wakeup_fifo.analysis_export);
  m_aon_agent.monitor.reset_req_port.connect(scoreboard.reset_req_fifo.analysis_export);
  m_fast_agent.monitor.active_port.connect(scoreboard.active_fifo.analysis_export);
  m_fast_agent.monitor.low_power_port.connect(scoreboard.low_power_fifo.analysis_export);
  m_fast_agent.monitor.intr_port.connect(scoreboard.intr_fifo.analysis_export);
  m_fast_agent.monitor.stim_port.connect(scoreboard.stim_fifo.analysis_export);
  m_fast_agent.monitor.fsm_port.connect(scoreboard.fsm_fifo.analysis_export);
  m_fast_agent.monitor.fsm_port.connect(virtual_sequencer.fsm_fifo.analysis_export);

  // The same publications also reach the sequencer, which is how a sequence waits for something
  // the device announced rather than watching a pin.
  m_fast_agent.monitor.active_port.connect(virtual_sequencer.active_fifo.analysis_export);
  m_fast_agent.monitor.low_power_port.connect(virtual_sequencer.low_power_fifo.analysis_export);
  m_fast_agent.monitor.intr_port.connect(virtual_sequencer.intr_fifo.analysis_export);
  m_aon_agent.monitor.clk_valid_port.connect(virtual_sequencer.clk_valid_fifo.analysis_export);

  // Collected here rather than in build_phase: an alert agent fills in its own interface handle
  // during its build, which runs after this environment's.
  foreach (cfg.m_alert_agent_cfgs[alert_name]) begin
    cfg.m_aon_agent_cfg.alert_clk_rst_vifs.push_back(
        cfg.m_alert_agent_cfgs[alert_name].vif.clk_rst_async_if);
  end

  virtual_sequencer.aon_sequencer_h  = m_aon_agent.sequencer;
  virtual_sequencer.fast_sequencer_h = m_fast_agent.sequencer;
endfunction : connect_phase


// The register access layer keeps its own idea of whether reset is asserted and abandons a transfer
// in flight, and nothing in the reset-safe path tells it. Without this a transfer issued as reset
// lands waits out its full timeout.
//
// The domain watched is the bus agent's, the fast domain, not the power-on domain: they assert at
// different times. csr_utils_pkg is told directly rather than through cfg.reset_asserted(), which
// also sets cfg.under_reset.
task pwrmgr_rst_safe_env::run_phase(uvm_phase phase);
  // Forked before the call below so this still starts if a base class ever gains a run_phase
  // that blocks.
  fork
    forever begin
      cfg.fast_reset_domain.wait_reset_assert();
      csr_utils_pkg::reset_asserted();
      cfg.fast_reset_domain.wait_reset_deassert();
      csr_utils_pkg::reset_deasserted();
    end
  join_none

  super.run_phase(phase);
endtask : run_phase
