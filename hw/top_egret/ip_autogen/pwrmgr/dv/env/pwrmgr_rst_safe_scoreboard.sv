// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe scoreboard for the power manager.
//
// Everything it learns arrives as a transaction from one of the two monitors or from the bus.
// It samples no signal and waits on no clock edge, so the only thing that can wake a worker is
// a publication or a reset.
class pwrmgr_rst_safe_scoreboard extends cip_rst_safe_scoreboard #(
    .CFG_T(pwrmgr_env_cfg),
    .RAL_T(pwrmgr_reg_block),
    .COV_T(pwrmgr_rst_safe_env_cov)
  );

  `uvm_component_utils(pwrmgr_rst_safe_scoreboard)
  `uvm_component_new

  // The events the model will predict from first. The remaining publications, the AST request,
  // the glitch, the strap sample and the peer requests, are not consumed yet; they are left
  // unconnected rather than drained and discarded, so the gap is visible.
  uvm_tlm_analysis_fifo #(pwrmgr_wakeup_item)    wakeup_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_reset_req_item) reset_req_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_active_item)    active_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      low_power_fifo;
  uvm_tlm_analysis_fifo #(pwrmgr_flag_item)      intr_fifo;

  protected pwrmgr_wakeup_item    last_wakeup;
  protected pwrmgr_reset_req_item last_reset_req;
  protected pwrmgr_active_item    last_active;
  protected pwrmgr_flag_item      last_intr;

  // What the device is expected to have recorded, built from the stimulus it was given rather
  // than from anything it reports. The registers below are written by hardware, so a read is
  // compared against this instead of against the mirror.
  protected bit       in_low_power;
  protected wakeups_t exp_wake_status;
  protected wakeups_t exp_wake_info_reasons;
  protected bit       exp_intr_wakeup;

  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void reset(string kind = "HARD");

  extern virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);

  extern protected task process_wakeups();
  extern protected task process_reset_reqs();
  extern protected task process_active();
  extern protected task process_low_power();
  extern protected task process_interrupts();
endclass : pwrmgr_rst_safe_scoreboard


function void pwrmgr_rst_safe_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  wakeup_fifo    = new("wakeup_fifo", this);
  reset_req_fifo = new("reset_req_fifo", this);
  active_fifo    = new("active_fifo", this);
  low_power_fifo = new("low_power_fifo", this);
  intr_fifo      = new("intr_fifo", this);
endfunction : build_phase


task pwrmgr_rst_safe_scoreboard::run_phase(uvm_phase phase);
  super.run_phase(phase);
  fork
    process_wakeups();
    process_reset_reqs();
    process_active();
    process_low_power();
    process_interrupts();
  join_none
endtask : run_phase


function void pwrmgr_rst_safe_scoreboard::reset(string kind = "HARD");
  super.reset(kind);
  wakeup_fifo.flush();
  reset_req_fifo.flush();
  active_fifo.flush();
  low_power_fifo.flush();
  intr_fifo.flush();
  last_wakeup    = null;
  last_reset_req = null;
  last_active    = null;
  last_intr      = null;

  in_low_power          = 1'b0;
  exp_wake_status       = '0;
  exp_wake_info_reasons = '0;
  exp_intr_wakeup       = 1'b0;
endfunction : reset


// A wakeup raised while the device is in low power, and enabled, is what the device records and
// what brings it back. Predicting from the stimulus rather than from what the device reports is
// what makes the register reads below a check rather than a tautology.
task pwrmgr_rst_safe_scoreboard::process_wakeups();
  forever begin
    wakeups_t enabled;

    wakeup_fifo.get(last_wakeup);
    `DV_CHECK_FATAL(!in_reset(), "Wakeup observed while the power-on reset is asserted")

    enabled = last_wakeup.wakeups & wakeups_t'(`gmv(ral.wakeup_en[0]));
    // The status register follows rather than remembers: the device drives it with its write
    // enable tied high, so it shows the wakeups raised and enabled at this moment and drops them
    // again when they go away. It does not hold the cause of a wake.
    exp_wake_status = enabled;

    // The recorded reasons are the ones that accumulate, and only inside the window the device
    // opens when it enters low power. They are cleared by writing to their own register.
    if (in_low_power && enabled != '0) begin
      exp_intr_wakeup = 1'b1;
      if (!`gmv(ral.wake_info_capture_dis)) exp_wake_info_reasons |= enabled;
    end
  end
endtask : process_wakeups


task pwrmgr_rst_safe_scoreboard::process_reset_reqs();
  forever begin
    reset_req_fifo.get(last_reset_req);
    `DV_CHECK_FATAL(!in_reset(), "Reset request observed while the power-on reset is asserted")
  end
endtask : process_reset_reqs


task pwrmgr_rst_safe_scoreboard::process_active();
  forever begin
    active_fifo.get(last_active);
    `DV_CHECK_FATAL(!in_reset(),
                    "Device activity observed while the power-on reset is asserted")
  end
endtask : process_active


task pwrmgr_rst_safe_scoreboard::process_interrupts();
  forever begin
    intr_fifo.get(last_intr);
    `DV_CHECK_FATAL(!in_reset(), "Interrupt observed while the power-on reset is asserted")

    // The pin follows the recorded interrupt qualified by its enable.
    if (last_intr.value) begin
      `DV_CHECK_EQ(exp_intr_wakeup, 1'b1,
                   "The device raised the wakeup interrupt with no wakeup to account for it")
      `DV_CHECK_EQ(`gmv(ral.intr_enable.wakeup), 1'b1,
                   "The device raised the wakeup interrupt while it was disabled")
    end
  end
endtask : process_interrupts


task pwrmgr_rst_safe_scoreboard::process_low_power();
  pwrmgr_flag_item item;

  forever begin
    low_power_fifo.get(item);
    `DV_CHECK_FATAL(!in_reset(), "Low power observed while the power-on reset is asserted")
    in_low_power = item.value;
  end
endtask : process_low_power


// Register traffic. A write is predicted when it is issued; a read is compared against the
// mirror unless the register is one the hardware writes, since the value of those is decided by
// what the device did rather than by what software last wrote. Predicting those is the
// reference model's work, which checkpoint 2 adds, so they are read and recorded here without
// being checked rather than checked against a value this scoreboard cannot yet know.
task pwrmgr_rst_safe_scoreboard::process_tl_access(tl_seq_item item, tl_channels_e channel,
                                                   string ral_name);
  uvm_reg        csr;
  bit            write = item.is_write();
  uvm_reg_addr_t csr_addr = cfg.ral_models[ral_name].get_word_aligned_addr(item.a_addr);
  bit            addr_phase_write = (write && channel == AddrChannel);
  bit            data_phase_write = (write && channel == DataChannel);
  bit            data_phase_read = (!write && channel == DataChannel);
  bit            do_read_check = 1'b1;

  if (!(csr_addr inside {cfg.ral_models[ral_name].csr_addrs})) begin
    `uvm_fatal(`gfn, $sformatf("Access to an address with no register: 0x%0h", csr_addr))
  end
  csr = cfg.ral_models[ral_name].default_map.get_reg_by_offset(csr_addr);
  `DV_CHECK_NE_FATAL(csr, null)

  if (addr_phase_write) begin
    void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));
  end

  case (csr.get_name())
    // Written by hardware, so a read is compared against what the model expects rather than
    // against the mirror.
    "wake_status": begin
      if (data_phase_read) begin
        `DV_CHECK_EQ(wakeups_t'(item.d_data), exp_wake_status,
                     "wake_status does not match the expected value")
      end
      do_read_check = 1'b0;
    end
    "wake_info": begin
      if (data_phase_read) begin
        `DV_CHECK_EQ(wakeups_t'(get_field_val(ral.wake_info.reasons, item.d_data)),
                     exp_wake_info_reasons,
                     "wake_info reasons do not match the expected value")
      end
      // Writing a one clears the recorded reasons, and capture has to be disabled to do it.
      if (data_phase_write && `gmv(ral.wake_info_capture_dis)) exp_wake_info_reasons = '0;
      do_read_check = 1'b0;
    end
    "intr_state": begin
      if (data_phase_read) begin
        `DV_CHECK_EQ(bit'(get_field_val(ral.intr_state.wakeup, item.d_data)), exp_intr_wakeup,
                     "intr_state wakeup does not match the expected value")
      end
      // Write one to clear.
      if (data_phase_write && get_field_val(ral.intr_state.wakeup, item.a_data)) begin
        exp_intr_wakeup = 1'b0;
      end
      do_read_check = 1'b0;
    end
    // Still unpredicted: these need the rest of the model, which is checkpoint 2.
    "ctrl_cfg_regwen", "reset_status", "escalate_reset_status", "fault_status", "control": begin
      do_read_check = 1'b0;
    end
    // Write only, or self clearing, so a read tells nothing about what was written.
    "intr_test", "alert_test", "cfg_cdc_sync": begin
      do_read_check = 1'b0;
    end
    default: ;
  endcase

  if (data_phase_read) begin
    if (do_read_check) begin
      `DV_CHECK_EQ(csr.get_mirrored_value(), item.d_data,
                   $sformatf("register %0s read back a value it was not written", csr.get_full_name()))
    end
    void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));
  end
endtask : process_tl_access
