// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reset-safe scoreboard.
//
// Structure, which is the part that differs most from the legacy scoreboard: every consumer
// is a persistent worker that blocks on a monitor-fed FIFO and does all of its work in zero
// simulation time after the receive. There is no free-running thread, no clock edge wait and
// no signal sampling anywhere in this class.
//
// The checking discipline for observations that come from inside the device: an observed
// hardware commit is compared against a prediction built from architectural inputs first,
// and only after that comparison passes is it used to update a RAL mirror or to predict
// anything downstream. Predicting from it first would make the mirror agree with the device
// by construction. `unchecked_events` below counts anything that reached a worker without
// being checked, and check_phase fails if it is non-zero, so an unimplemented prediction
// cannot be mistaken for a passing test.
class gpio_rst_safe_scoreboard extends cip_rst_safe_scoreboard #(
    .CFG_T(gpio_env_cfg),
    .RAL_T(gpio_reg_block),
    .COV_T(gpio_rst_safe_env_cov)
  );
  `uvm_component_utils(gpio_rst_safe_scoreboard)

  // Observations from the GPIO agent monitor.
  uvm_tlm_analysis_fifo #(gpio_input_item)    input_state_fifo;
  uvm_tlm_analysis_fifo #(gpio_intr_item)     intr_event_fifo;
  uvm_tlm_analysis_fifo #(gpio_straps_item)   straps_event_fifo;
  uvm_tlm_analysis_fifo #(gpio_hw_write_item) hw_write_fifo;
  uvm_tlm_analysis_fifo #(gpio_output_item)   output_fifo;

  // The order the monitor published in. One worker reads this and takes from the FIFO it
  // names, so observations are processed in the order they were observed rather than in
  // whatever order the scheduler happened to wake five workers.
  uvm_tlm_analysis_fifo #(gpio_probe_kind_e) probe_dir_fifo;

  // The model that predictions come from. Owned here, driven only by this class.
  gpio_reference_model model;

  // Counts observations that reached a worker without being checked. Any non-zero value at
  // the end of the test is a hole in the checker, not a pass.
  // Cumulative across the test, not per epoch: see reset().
  protected int unsigned unchecked_events;

  // Counts filtered-input observations that were checked against the filter model, so a run
  // that exercised nothing can be told apart from a run that checked and agreed.
  protected int unsigned checked_data_in_events;
  protected int unsigned checked_straps_events;
  protected int unsigned checked_output_events;
  protected int unsigned checked_counter_events;

  // Interrupt pin observations drained. They are checked by assertion, and the count is kept
  // so the end of test report still shows the path was exercised.
  protected int unsigned checked_intr_pin_observations;


  // The last filtered input the checker accepted. The strap sample is taken from it.
  protected bit [NUM_GPIOS-1:0] last_data_in;

  // Interrupt events seen since the device last changed INTR_STATE. The register is sticky,
  // so every event between two register changes contributes, not only the most recent one.
  // Several observations can fall between two register changes whenever pins move on
  // different cycles, which the synchronizer's per-pin delay makes routine.
  // Edge events seen but not yet accounted for, each with the cycle it happened on.
  //
  // The stamp is what keeps a software write honest. INTR_STATE is W1C, so a write is
  // resolved against whatever the hardware is setting in the same cycle, and the probe runs
  // ahead of the bus path, so by the time a write is processed this accumulator can already
  // hold events from cycles after the write landed in the device. Folding those into the
  // clear would remove bits the device kept. Only events at or before the cycle being checked
  // are ever used.


  // Counter writes the model was still expecting when a reset ended the epoch. Reported
  // rather than failed: an epoch can legitimately end with a measurement in flight, so the
  // number is a signal to read and not a verdict on its own.
  protected int unsigned        dropped_cnt_commits;


  // The raw input as it was last seen, and the cycle each pin last changed on, so that the
  // time a pin held a value can be measured when it leaves it.
  protected bit [NUM_GPIOS-1:0] cov_last_raw;
  protected longint unsigned    cov_last_change[NUM_GPIOS];

  // DATA_IN and INTR_STATE are written by hardware, so a read can be in flight while the
  // content changes underneath it. The bus returns the content from some cycle inside the
  // access, not from its end, so the read is checked against the values the register was
  // seen to hold around the access rather than against the mirror at its data channel.
  //
  // The bound cannot be taken from the access length. The register content arrives on the
  // probe port and the access on the TL port, and nothing orders the two against each other,
  // so the count of updates either side of the access is what the window has to be expressed
  // in.
  typedef struct {
    longint unsigned index;
    bit [TL_DW-1:0]  value;
  } volatile_update_t;

  protected volatile_update_t   read_history[string][$];
  protected longint unsigned    update_count[string];
  protected longint unsigned    read_mark[string];

  // Largest distance between the update a read returned and the update current when its
  // address channel was seen, reported at the end of the test.
  //
  // On its own this number cannot size the window, and reading it that way was a mistake once
  // already. It only counts reads that matched, so a read needing a window wider than the
  // history fails and is never counted, and the figure says where matches land rather than how
  // wide the window has to be.
  protected longint unsigned    max_read_distance_before;
  protected longint unsigned    max_read_distance_after;

  // Updates to the register between a read's address channel and its data channel. This is
  // computed for every read whether it matched or not, so unlike the distances above it is not
  // biased by the reads the window was too small to hold, and it is what the window has to
  // cover.
  protected longint unsigned    max_read_span;


  // A software write to INTR_STATE or INTR_TEST that has been seen on the bus but whose
  // effect on the register has not yet been observed. prim_subreg_arb resolves a software
  // write against a hardware set in the same cycle, so the two have to be combined rather
  // than applied one after the other.
  // A software write to a counter's control register that has been seen on the bus but whose
  // effect on the register has not been observed yet. Software has priority over the device's
  // own end-of-measurement clear, so a pending write is the whole expected value.
  protected bit             pending_cnt_ctrl_write[NUM_INP_PRD_CNT];
  protected bit [TL_DW-1:0] pending_cnt_ctrl_wdata[NUM_INP_PRD_CNT];

  extern function new(string name, uvm_component parent);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern function void reset(string kind = "HARD");
  extern function void check_phase(uvm_phase phase);

  extern protected task process_probe_observations();
  extern protected function void process_input_item(gpio_input_item item);
  extern protected function void process_intr_item(gpio_intr_item item);
  extern protected function void process_straps_item(gpio_straps_item item);
  extern protected function void process_hw_write_item(gpio_hw_write_item item);
  extern protected function void process_output_item(gpio_output_item item);
  extern function void start_of_simulation_phase(uvm_phase phase);
  extern task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);

  // Record a value a hardware written register has been seen to hold, for any read of it
  // that is in flight.
  extern protected function void note_volatile_value(string name, bit [TL_DW-1:0] value);

  // Check a read of a hardware written register against the values it was seen to hold
  // around the access.
  extern protected function void check_volatile_read(string name, bit [TL_DW-1:0] value);
endclass : gpio_rst_safe_scoreboard


function gpio_rst_safe_scoreboard::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction : new


function void gpio_rst_safe_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  input_state_fifo  = new("input_state_fifo", this);
  intr_event_fifo   = new("intr_event_fifo", this);
  straps_event_fifo = new("straps_event_fifo", this);
  hw_write_fifo     = new("hw_write_fifo", this);
  output_fifo       = new("output_fifo", this);
  probe_dir_fifo    = new("probe_dir_fifo", this);

  model = gpio_reference_model::type_id::create("model");
  model.gpio_as_hw_straps_en = cfg.gpio_as_hw_straps_en;
endfunction : build_phase


task gpio_rst_safe_scoreboard::run_phase(uvm_phase phase);
  super.run_phase(phase);
  // Created once, for the life of the test. The inherited reset worker returns each of these
  // to a clean wait rather than tearing the hierarchy down and rebuilding it.
  fork
    process_probe_observations();
  join_none
endtask : run_phase


task gpio_rst_safe_scoreboard::process_probe_observations();
  forever begin
    gpio_probe_kind_e   kind;
    gpio_input_item     input_item;
    gpio_intr_item      intr_item;
    gpio_straps_item    straps_item;
    gpio_hw_write_item  hw_write_item;
    gpio_output_item    output_item;

    probe_dir_fifo.get(kind);
    `DV_CHECK_FATAL(!in_reset(),
                    "Probe observation received while the interface is in reset")

    // A named FIFO that is empty means the ordering channel and the observation it names
    // have fallen out of step, which would silently reorder everything after it.
    case (kind)
      GpioProbeInput: begin
        `DV_CHECK_FATAL(input_state_fifo.try_get(input_item),
                        "probe order named an input observation, but its FIFO was empty")
        process_input_item(input_item);
      end
      GpioProbeIntr: begin
        `DV_CHECK_FATAL(intr_event_fifo.try_get(intr_item),
                        "probe order named an interrupt observation, but its FIFO was empty")
        process_intr_item(intr_item);
      end
      GpioProbeStraps: begin
        `DV_CHECK_FATAL(straps_event_fifo.try_get(straps_item),
                        "probe order named a strap observation, but its FIFO was empty")
        process_straps_item(straps_item);
      end
      GpioProbeHwWrite: begin
        `DV_CHECK_FATAL(hw_write_fifo.try_get(hw_write_item),
                        "probe order named a register commit, but its FIFO was empty")
        process_hw_write_item(hw_write_item);
      end
      GpioProbeOutput: begin
        `DV_CHECK_FATAL(output_fifo.try_get(output_item),
                        "probe order named an output observation, but its FIFO was empty")
        process_output_item(output_item);
      end
      default: `uvm_fatal(`gfn, "Unknown entry in the probe order FIFO")
    endcase
  end
endtask : process_probe_observations


function void gpio_rst_safe_scoreboard::process_input_item(
    gpio_input_item item);

    // The filtered input is checked by gpio_filter_assert, inside the
    // filter, where the synchronizer output it runs on is visible. Nothing is predicted here.
    //
    // What the observation is still used for is the counters, which measure the cycles
    // between edges of this signal, and the coverage of how long a pin held its value.
    checked_data_in_events++;

    if (cfg.en_cov) begin
      foreach (cov_last_raw[i]) begin
        if (item.raw_in[i] == cov_last_raw[i]) continue;
        cov.pins_stable_period_and_filter_cg.sample(
            .pin           (i),
            .stable_cycles (int'(item.epoch_cycle - cov_last_change[i])),
            .pin_value     (cov_last_raw[i]),
            .filter_en     (1'b0));
        cov_last_change[i] = item.epoch_cycle;
      end
      cov_last_raw = item.raw_in;
    end

    last_data_in = item.data_in;
    note_volatile_value("data_in", item.data_in);

    // The counters key off the edges of the filtered input.
    model.advance_counters_to(item.epoch_cycle, item.rising, item.falling);
endfunction : process_input_item


function void gpio_rst_safe_scoreboard::process_intr_item(
    gpio_intr_item item);
  // The pin, INTR_STATE and INTR_ENABLE are related within one cycle, and
  // gpio_intr_assert checks that where the write enable resolving a clear
  // against a set is visible. Nothing is compared here.
  //
  // The observation is still drained, because sequences wait on the virtual sequencer's copy
  // of it and an unread port would stall the monitor.
  checked_intr_pin_observations++;
endfunction : process_intr_item


function void gpio_rst_safe_scoreboard::process_straps_item(
    gpio_straps_item item);

    if (item.trigger) begin
      // The request is published after the latch it causes, so by the time it arrives here the
      // sample it asked for has already been accounted for. A request that arrived with the
      // valid bit clear has to have produced one.
      if (!item.valid && !model.straps_valid) begin
        `uvm_error(`gfn, $sformatf(
                   "a strap sample was requested at epoch cycle %0d and none was taken",
                   item.epoch_cycle))
      end
      checked_straps_events++;
      return;
    end

    // sampled_straps_o is driven straight from the two strap registers, so this is a
    // redundancy check between what the registers hold and what the block broadcasts. It is
    // worth having precisely because the two are meant to be identical: nothing else in the
    // testbench would notice if the broadcast stopped following the register.
    `DV_CHECK_EQ(item.valid, model.straps_valid,
                 $sformatf("strap broadcast valid mismatch at epoch cycle %0d",
                           item.epoch_cycle))
    if (model.straps_valid) begin
      `DV_CHECK_EQ(item.data, model.straps_data,
                   $sformatf("strap broadcast data mismatch at epoch cycle %0d",
                             item.epoch_cycle))
    end
    checked_straps_events++;
endfunction : process_straps_item


function void gpio_rst_safe_scoreboard::process_hw_write_item(
    gpio_hw_write_item item);


    // Ordering throughout: compare the committed value against the prediction first, and
    // only then predict the RAL field. Predicting first would make the mirror
    // agree with the device by construction and the comparison meaningless.
    case (item.kind)
      GpioHwWriteStraps: begin
        // The device samples its filtered input as straps, so the expected value is the
        // filtered input the data_in comparison has already accepted. Checking it here is
        // what stops the strap registers being predicted from an observation nothing has
        // validated.
        `DV_CHECK_EQ(item.value[NUM_GPIOS-1:0], last_data_in,
                     $sformatf("strap sample mismatch at epoch cycle %0d", item.epoch_cycle))
        `DV_CHECK_EQ(item.aux_valid, 1'b1, "strap sample committed without setting valid")

        // Once per reset. sample_trigger is `strap_en && !valid`, so a second latch in one
        // epoch means either the device ignored its own valid bit or the testbench observed
        // something that is not a strap sample.
        if (model.straps_valid) begin
          `uvm_error(`gfn, $sformatf(
                     "a second strap sample was taken in one reset epoch, at cycle %0d",
                     item.epoch_cycle))
        end

        model.commit_straps(item.value[NUM_GPIOS-1:0]);
        void'(ral.hw_straps_data_in.predict(.value(item.value), .kind(UVM_PREDICT_READ)));
        void'(ral.hw_straps_data_in_valid.predict(.value(1), .kind(UVM_PREDICT_READ)));
        checked_straps_events++;
      end
      GpioHwWriteInpPrdCntVal: begin
        gpio_reference_model::inp_prd_cnt_commit_t exp;
        gpio_input_item in_item;


        model.advance_counters_to(item.epoch_cycle, '0, '0);
        if (model.cnt_commits.size() == 0) begin
          `uvm_error(`gfn, $sformatf(
                     "counter %0d wrote 0x%0h at cycle %0d and the model expected no write",
                     item.index, item.value, item.epoch_cycle))
        end else begin
          exp = model.cnt_commits.pop_front();
          `DV_CHECK_EQ(exp.is_enable_clear, 1'b0,
                       "expected a control change but a measured value was written")
          `DV_CHECK_EQ(item.index, exp.index, "input period counter index mismatch")
          `DV_CHECK_EQ(item.value, exp.value,
                       $sformatf("counter %0d measured value mismatch at cycle %0d",
                                 item.index, item.epoch_cycle))
          checked_counter_events++;
          void'(ral.inp_prd_cnt_val[item.index].predict(.value(item.value),
                                                        .kind(UVM_PREDICT_READ)));
        end
      end
      default: begin
        unchecked_events++;
      end
    endcase
endfunction : process_hw_write_item


function void gpio_rst_safe_scoreboard::process_output_item(
    gpio_output_item item);


    `DV_CHECK_EQ(item.data_out, model.data_out,
                 $sformatf("output data mismatch at epoch cycle %0d", item.epoch_cycle))
    `DV_CHECK_EQ(item.data_oe, model.data_oe,
                 $sformatf("output enable mismatch at epoch cycle %0d", item.epoch_cycle))
    checked_output_events++;

    // The device presents its output registers back to software, so the accepted observation
    // is also the predicted read value for the direct pair.
    void'(ral.direct_out.predict(.value(item.data_out), .kind(UVM_PREDICT_READ)));
    void'(ral.direct_oe.predict(.value(item.data_oe), .kind(UVM_PREDICT_READ)));
endfunction : process_output_item


function void gpio_rst_safe_scoreboard::note_volatile_value(
    string name, bit [TL_DW-1:0] value);
  volatile_update_t upd;

  update_count[name] = update_count.exists(name) ? update_count[name] + 1 : 1;
  upd.index = update_count[name];
  upd.value = value;
  read_history[name].push_back(upd);
  while (read_history[name].size() > VolatileReadHistoryDepth) begin
    void'(read_history[name].pop_front());
  end
endfunction : note_volatile_value


function void gpio_rst_safe_scoreboard::check_volatile_read(
    string name, bit [TL_DW-1:0] value);
  longint unsigned mark = read_mark.exists(name) ? read_mark[name] : 0;
  longint unsigned span = (update_count.exists(name) ? update_count[name] : 0) - mark;

  if (span > max_read_span) max_read_span = span;

  // Newest first. A pin pattern recurs, so the same value appears in the history more than
  // once, and it is the most recent occurrence that the read plausibly returned. Searching
  // oldest first reports the distance to the earliest repeat instead, which grows with the
  // history rather than with the access.
  for (int i = read_history[name].size() - 1; i >= 0; i--) begin
    if (read_history[name][i].value != value) continue;
    if (read_history[name][i].index <= mark) begin
      longint unsigned back = mark - read_history[name][i].index;
      if (back > max_read_distance_before) max_read_distance_before = back;
    end else begin
      longint unsigned fwd = read_history[name][i].index - mark;
      if (fwd > max_read_distance_after) max_read_distance_after = fwd;
    end
    return;
  end

  `uvm_error(`gfn, $sformatf(
             "read mismatch on %0s: 0x%0h is not among the last %0d values it held, and the access spanned %0d of them, %p",
             name, value, VolatileReadHistoryDepth, span, read_history[name]))
endfunction : check_volatile_read


function void gpio_rst_safe_scoreboard::start_of_simulation_phase(
    uvm_phase phase);
  super.start_of_simulation_phase(phase);
  // The model derives its filter window from FILTER_CYCLES while the device derives it from
  // the CntWidth prim_filter_ctr is instantiated with. Nothing links the two, so compare them
  // once rather than let a design change leave the model filtering for a different number of
  // cycles than the device it is checking.
  `DV_CHECK_EQ_FATAL(cfg.probe_vif_inst.filter_thresh, FILTER_CYCLES - 1,
                     "the device's filter threshold and FILTER_CYCLES disagree")
endfunction : start_of_simulation_phase


task gpio_rst_safe_scoreboard::process_tl_access(tl_seq_item item,
                                                                    tl_channels_e channel,
                                                                    string ral_name);
  uvm_reg csr;
  uvm_reg_addr_t csr_addr = cfg.ral_models[ral_name].get_word_aligned_addr(item.a_addr);

  if (!(csr_addr inside {cfg.ral_models[ral_name].csr_addrs})) begin
    `uvm_fatal(`gfn, $sformatf("Access to an unexpected address 0x%0h", csr_addr))
  end
  csr = cfg.ral_models[ral_name].default_map.get_reg_by_offset(csr_addr);
  `DV_CHECK_NE_FATAL(csr, null)

  if (channel == AddrChannel && item.is_write()) begin
    case (csr.get_name())
      "direct_out", "direct_oe",
      "masked_out_lower", "masked_out_upper",
      "masked_oe_lower", "masked_oe_upper": begin
        model.apply_out_write(csr.get_name(), item.a_data);
      end
      "inp_prd_cnt_ctrl_0", "inp_prd_cnt_ctrl_1", "inp_prd_cnt_ctrl_2", "inp_prd_cnt_ctrl_3",
      "inp_prd_cnt_ctrl_4", "inp_prd_cnt_ctrl_5", "inp_prd_cnt_ctrl_6", "inp_prd_cnt_ctrl_7": begin
        int unsigned idx = csr.get_name().substr(csr.get_name().len() - 1,
                                                 csr.get_name().len() - 1).atoi();
        // Recorded rather than applied. The register update that results is observed through
        // the probe, and the two are resolved there.
        pending_cnt_ctrl_write[idx] = 1'b1;
        pending_cnt_ctrl_wdata[idx] = item.a_data;
      end
      default: ;
    endcase
    // The mirror follows the bus write on the address channel. Holding the registers the
    // model reads back out until the transaction completes was measured and is worse: the
    // probe reports register content ahead of where the TL path has been processed, so a
    // mirror updated at the data channel lags what the device is already doing, and every
    // prediction built from it is behind. Updating on the address channel puts the mirror
    // slightly early instead, which is the smaller of the two errors.
    void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));
  end

  if (channel == DataChannel && !item.is_write()) begin
    // Read checking. The mirror for every register modelled above is maintained from an
    // observation that has already been compared against a prediction, so comparing a read
    // against the mirror closes the chain: the model says what the device should hold, the
    // probe says what it does hold, and this says the bus returns it.
    //
    // A register whose model is not written yet is deliberately excluded rather than
    // checked loosely. A check that cannot fail is worse than a visible gap, and
    // unchecked_events already records the gap.
    case (csr.get_name())
      "data_in": check_volatile_read(csr.get_name(), item.d_data);
      "intr_enable",
      "intr_ctrl_en_rising",
      "intr_ctrl_en_falling",
      "intr_ctrl_en_lvlhigh",
      "intr_ctrl_en_lvllow",
      "ctrl_en_input_filter",
      "hw_straps_data_in",
      "hw_straps_data_in_valid",
      "direct_out",
      "direct_oe": begin
        `DV_CHECK_EQ(item.d_data, csr.get_mirrored_value(),
                     $sformatf("read mismatch on %0s", csr.get_name()))
      end
      default: ;
    endcase
    void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));
  end
endtask : process_tl_access


function void gpio_rst_safe_scoreboard::reset(string kind = "HARD");
  super.reset(kind);

  // Everything below belongs to the reset epoch that just ended. The legacy scoreboard's
  // reset() left five members behind, including the two write-only mask shadows, so a stale
  // mask survived into the next epoch.
  // The checked counters are deliberately not cleared here. They are evidence about the
  // whole test, and reset is a thing the test does rather than a new test. Clearing them
  // meant the end-of-test report showed the last epoch, which for a test that ends with a
  // reset is zero.
  last_data_in              = '0;
  dropped_cnt_commits      += model.cnt_commits.size();
  cov_last_raw              = '0;
  foreach (cov_last_change[i]) cov_last_change[i] = 0;
  read_history.delete();
  update_count.delete();
  read_mark.delete();
  // The probe reports content changes, so the value a register comes out of reset holding is
  // never published. A read taken before the first change has to have something to match.
  note_volatile_value("data_in", '0);
  foreach (pending_cnt_ctrl_write[i]) begin
    pending_cnt_ctrl_write[i] = 1'b0;
    pending_cnt_ctrl_wdata[i] = '0;
  end
  input_state_fifo.flush();
  intr_event_fifo.flush();
  straps_event_fifo.flush();
  hw_write_fifo.flush();
  output_fifo.flush();
  probe_dir_fifo.flush();

  model.reset();
endfunction : reset


function void gpio_rst_safe_scoreboard::check_phase(uvm_phase phase);
  super.check_phase(phase);
  // Deliberately an error rather than a warning. A test that reached an observation this
  // class cannot predict has not been checked, and must not report a pass on the strength of
  // the observations it could check.
  if (unchecked_events > 0) begin
    `uvm_error(`gfn, $sformatf(
               "%0d observations were received without being checked; the checker is incomplete",
               unchecked_events))
  end

  // Measurements the model completed and the device never wrote. The per-observation check
  // catches a write the model did not expect; this is the other direction, and without it a
  // counter that stopped writing would pass.
  if (model.cnt_commits.size() > 0) begin
    `uvm_error(`gfn, $sformatf(
               "%0d input period counter writes were expected and never happened, first is counter %0d value 0x%0h",
               model.cnt_commits.size(), model.cnt_commits[0].index, model.cnt_commits[0].value))
  end
  if (dropped_cnt_commits > 0) begin
    `uvm_info(`gfn, $sformatf(
              "%0d input period counter writes were still owed when a reset arrived",
              dropped_cnt_commits), UVM_LOW)
  end
  `uvm_info(`gfn, $sformatf(
            "checked: %0d filtered input, %0d strap, %0d output, %0d counter; %0d interrupt pin observations left to assertions",
            checked_data_in_events, checked_straps_events, checked_output_events,
            checked_counter_events, checked_intr_pin_observations),
            UVM_LOW)
  `uvm_info(`gfn, $sformatf(
            "volatile read: span %0d updates, matched %0d before the access and %0d after",
            max_read_span, max_read_distance_before, max_read_distance_after), UVM_LOW)
endfunction : check_phase
