// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Reference model for the ${module_instance_name} input path and its consequences.
//
// It holds the predictions the scoreboard compares observations against. Keeping it out of
// the scoreboard leaves that class a set of FIFO workers and gives the build-time
// elaboration parameters a single consumer.
//
// The model contains no clock period and consults no simulation time. It is advanced in
// clock cycles by observations that carry an epoch cycle, so changing the elaboration moves
// the observations rather than invalidating the model.
class ${module_instance_name}_reference_model extends uvm_object;
  `uvm_object_utils(${module_instance_name}_reference_model)

  // prim_filter_ctr is instantiated with CntWidth 4 and thresh_i tied to all ones, so the
  // difference counter saturates at 15. FILTER_CYCLES is the window that produces, one more
  // than the threshold because the counter starts from zero.

  // Cycles of constant input after which the whole input path is in steady state: two for
  // the synchronizer to flush, FILTER_CYCLES for the difference counter to saturate, and a
  // margin. Advancing further than this with an unchanging input cannot change any state,
  // which is what makes the clamp in advance() exact rather than approximate.

  // Reported INTR_STATE changes kept for the interrupt pin lookup. The pin is one flop behind
  // the register, so a lookup only ever reaches back a cycle; the depth is for the case where
  // several changes carry the same or adjacent stamps.

  // Build-time elaboration of the device being modelled, set by the scoreboard at build.
  bit gpio_as_hw_straps_en;


  extern function new(string name = "");
  extern virtual function void reset();

% if num_inp_period_counters > 0:
  // Input period counter state, one set per counter, mirroring the design's three-state
  // machine, its prescaler and its sticky relevant-edge flop. Software configuration is
  // copied in when the scoreboard sees it written, because the model has no register access
  // of its own.
  typedef enum bit [1:0] {
    InpPrdCntDisabled,
    InpPrdCntPreOpeningEdge,
    InpPrdCntPreClosingEdge
  } inp_prd_cnt_state_e;

  typedef struct packed {
    bit       enable;
    bit       continuous;
    bit       polarity;
    bit [7:0] input_select;
    bit [7:0] prescaler;
  } inp_prd_cnt_cfg_t;

  // One committed change the counters are expected to make to a software-visible register.
  typedef struct {
    int unsigned     index;
    bit [TL_DW-1:0]  value;
    bit              is_enable_clear;
  } inp_prd_cnt_commit_t;

  inp_prd_cnt_cfg_t   cnt_cfg[NUM_INP_PRD_CNT];
  inp_prd_cnt_state_e cnt_state[NUM_INP_PRD_CNT];
  bit [31:0]          cnt_value[NUM_INP_PRD_CNT];
  bit [7:0]           cnt_prescaler[NUM_INP_PRD_CNT];
  bit                 cnt_edge_seen[NUM_INP_PRD_CNT];

  // Commits the counters are expected to make, in the order the design would make them. The
  // scoreboard pops one per observed commit and compares.
  inp_prd_cnt_commit_t cnt_commits[$];

  // Cycle the counters have been stepped to. Kept separate from the filter's cycle because
  // the counters are driven by the edges of the filtered input, which only the observations
  // report, while the filter is driven by the raw input.
  longint unsigned cnt_last_cycle;

  extern virtual function void set_inp_prd_cnt_cfg(int unsigned index,
                                                   bit [TL_DW-1:0] ctrl_value);
  extern virtual function bit [TL_DW-1:0] predicted_inp_prd_cnt_ctrl(int unsigned index);
  extern virtual function bit any_inp_prd_cnt_enabled();

  // Step the counters to `cycle`, applying the observed edges of the filtered input on that
  // cycle and no edges on the cycles before it. Between observations the filtered input is
  // by definition unchanged, so there are no edges to apply.
  extern virtual function void advance_counters_to(longint unsigned cycle,
                                                   bit [NUM_GPIOS-1:0] rising,
                                                   bit [NUM_GPIOS-1:0] falling);
  extern protected virtual function void advance_inp_prd_cnts(bit [NUM_GPIOS-1:0] rising,
                                                              bit [NUM_GPIOS-1:0] falling);
% endif

  // Strap latch. The device samples its filtered input as straps at most once per reset
  // cycle, on the first cycle strap_en is high while the valid bit is clear, and holds the
  // result until reset. `sample_trigger` in the design is `strap_en && !valid`, so the valid
  // bit is both the output of the latch and the thing that prevents a second one.
  bit                 straps_valid;
  bit [NUM_GPIOS-1:0] straps_data;

  extern virtual function void commit_straps(bit [NUM_GPIOS-1:0] data);

  // The device's output drive, maintained from the writes that change it. cio_gpio_q and
  // cio_gpio_en_q are updated only by a write to their register, with DIRECT taking priority
  // over the upper half and the upper half over the lower, and a masked write leaving the
  // bits its mask does not select alone.
  bit [NUM_GPIOS-1:0] data_out;
  bit [NUM_GPIOS-1:0] data_oe;

  extern virtual function void apply_out_write(string reg_name, bit [TL_DW-1:0] wdata);

endclass : ${module_instance_name}_reference_model


function ${module_instance_name}_reference_model::new(string name = "");
  super.new(name);
endfunction : new


function void ${module_instance_name}_reference_model::reset();
  // Every flop in the input path clears at reset: both synchronizer stages, the filter's
  // stored value, its input flop and its difference counter.
  // prim_intr_hw clears INTR_STATE at reset, so a pending interrupt does not survive into
  // the next epoch and neither does the model's idea of one.
  // Reset clears the valid bit, which is what re-arms the strap latch. Without that the
  // feature would sample once in the life of the device rather than once per reset.
  straps_valid          = 1'b0;
  straps_data           = '0;
  // Both output registers clear at reset, so the device drives nothing until software asks
  // it to.
  data_out              = '0;
  data_oe               = '0;
% if num_inp_period_counters > 0:
  // Every counter flop clears at reset, and so does the control register that configures it.
  foreach (cnt_cfg[i]) begin
    cnt_cfg[i]       = '0;
    // polarity resets to one, so a counter comes out of reset looking for a rising edge.
    cnt_cfg[i].polarity = 1'b1;
    cnt_state[i]     = InpPrdCntDisabled;
    cnt_value[i]     = '0;
    cnt_prescaler[i] = '0;
    cnt_edge_seen[i] = 1'b0;
  end
  cnt_commits.delete();
  cnt_last_cycle = 0;
% endif
endfunction : reset


% if num_inp_period_counters > 0:
function void ${module_instance_name}_reference_model::set_inp_prd_cnt_cfg(
    int unsigned index, bit [TL_DW-1:0] ctrl_value);
  // Field layout of INP_PRD_CNT_CTRL, taken from the register definition rather than from a
  // RAL handle the model does not have.
  cnt_cfg[index].enable       = ctrl_value[0];
  cnt_cfg[index].continuous   = ctrl_value[1];
  cnt_cfg[index].polarity     = ctrl_value[2];
  cnt_cfg[index].input_select = ctrl_value[15:8];
  cnt_cfg[index].prescaler    = ctrl_value[23:16];
endfunction : set_inp_prd_cnt_cfg


function bit [TL_DW-1:0] ${module_instance_name}_reference_model::predicted_inp_prd_cnt_ctrl(
    int unsigned index);
  return {8'd0, cnt_cfg[index].prescaler, cnt_cfg[index].input_select, 5'd0,
          cnt_cfg[index].polarity, cnt_cfg[index].continuous, cnt_cfg[index].enable};
endfunction : predicted_inp_prd_cnt_ctrl


function void ${module_instance_name}_reference_model::advance_counters_to(
    longint unsigned cycle, bit [NUM_GPIOS-1:0] rising, bit [NUM_GPIOS-1:0] falling);
  longint unsigned quiet_cycles;

  // As in advance_to(): observations arrive in order, so this only absorbs a repeat of the
  // cycle already applied.
  if (cycle <= cnt_last_cycle) return;

  quiet_cycles = cycle - cnt_last_cycle - 1;

  // With nothing enabled no state moves, so a long quiet span costs nothing. With a counter
  // running the prescaler advances every cycle and the span has to be walked.
  if (any_inp_prd_cnt_enabled()) begin
    repeat (quiet_cycles) advance_inp_prd_cnts('0, '0);
  end

  advance_inp_prd_cnts(rising, falling);
  cnt_last_cycle = cycle;
endfunction : advance_counters_to


function bit ${module_instance_name}_reference_model::any_inp_prd_cnt_enabled();
  foreach (cnt_cfg[i]) if (cnt_cfg[i].enable) return 1'b1;
  return 1'b0;
endfunction : any_inp_prd_cnt_enabled


function void ${module_instance_name}_reference_model::advance_inp_prd_cnts(
    bit [NUM_GPIOS-1:0] rising, bit [NUM_GPIOS-1:0] falling);
  foreach (cnt_cfg[i]) begin
    bit                 relevant_edge;
    bit                 prescaler_reached;
    bit                 clr, inc, edge_clr, val_de, enable_de;
    bit [7:0]           prescaler_d;
    bit                 edge_d;
    bit [31:0]          value_d;
    inp_prd_cnt_state_e state_d;
    int unsigned        sel;

    sel = cnt_cfg[i].input_select;
    // The design selects with a truncated index, so a select beyond the pin count wraps
    // rather than reading nothing.
    relevant_edge = cnt_cfg[i].polarity ? rising[sel % NUM_GPIOS] : falling[sel % NUM_GPIOS];

    prescaler_reached = (cnt_prescaler[i] == cnt_cfg[i].prescaler) && cnt_cfg[i].enable;

    if (!cnt_cfg[i].enable)      prescaler_d = '0;
    else if (prescaler_reached)  prescaler_d = '0;
    else                         prescaler_d = cnt_prescaler[i] + 8'd1;

    clr = 1'b0; inc = 1'b0; edge_clr = 1'b0; val_de = 1'b0; enable_de = 1'b0;
    state_d = cnt_state[i];

    case (cnt_state[i])
      InpPrdCntDisabled: begin
        if (cnt_cfg[i].enable) begin
          clr     = 1'b1;
          state_d = InpPrdCntPreOpeningEdge;
        end
      end
      InpPrdCntPreOpeningEdge: begin
        if (cnt_edge_seen[i]) begin
          edge_clr = 1'b1;
          state_d  = InpPrdCntPreClosingEdge;
        end
      end
      InpPrdCntPreClosingEdge: begin
        // Both the increment and the close only happen on a cycle the prescaler has reached
        // its threshold, so the measured value counts prescaler periods and not clocks.
        if (prescaler_reached) begin
          inc = 1'b1;
          if (cnt_edge_seen[i]) begin
            edge_clr = 1'b1;
            val_de   = 1'b1;
            clr      = 1'b1;
            if (!cnt_cfg[i].continuous) begin
              enable_de = 1'b1;
              state_d   = InpPrdCntDisabled;
            end
          end
        end
      end
      default: state_d = InpPrdCntDisabled;
    endcase

    if (!cnt_cfg[i].enable) begin
      clr      = 1'b1;
      edge_clr = 1'b1;
      state_d  = InpPrdCntDisabled;
    end

    // The register takes the value from before this cycle's increment, and the clear wins
    // over the increment, so a closing edge reports the periods that preceded it.
    value_d = cnt_value[i];
    if (clr)                                     value_d = '0;
    else if (inc && cnt_value[i] != '1)          value_d = cnt_value[i] + 32'd1;

    // A new edge takes precedence over the clear, so an edge arriving on the cycle the flop
    // is consumed is not lost.
    edge_d = cnt_edge_seen[i];
    if (relevant_edge)   edge_d = 1'b1;
    else if (edge_clr)   edge_d = 1'b0;

    if (val_de) begin
      cnt_commits.push_back('{index: i, value: cnt_value[i], is_enable_clear: 1'b0});
    end
    // The control content prediction is derived from cnt_cfg, so clearing the enable here is
    // all that is needed for the observed control change to be predicted.
    if (enable_de) cnt_cfg[i].enable = 1'b0;

    cnt_value[i]     = value_d;
    cnt_prescaler[i] = prescaler_d;
    cnt_edge_seen[i] = edge_d;
    cnt_state[i]     = state_d;
  end
endfunction : advance_inp_prd_cnts
% endif


function void ${module_instance_name}_reference_model::apply_out_write(
    string reg_name, bit [TL_DW-1:0] wdata);
  bit [15:0] data = wdata[15:0];
  bit [15:0] mask = wdata[31:16];

  case (reg_name)
    "direct_out": data_out = wdata[NUM_GPIOS-1:0];
    "direct_oe":  data_oe  = wdata[NUM_GPIOS-1:0];
    "masked_out_lower": data_out[15:0] = (mask & data) | (~mask & data_out[15:0]);
    "masked_out_upper": data_out[NUM_GPIOS-1:16] =
        (mask & data) | (~mask & data_out[NUM_GPIOS-1:16]);
    "masked_oe_lower": data_oe[15:0] = (mask & data) | (~mask & data_oe[15:0]);
    "masked_oe_upper": data_oe[NUM_GPIOS-1:16] =
        (mask & data) | (~mask & data_oe[NUM_GPIOS-1:16]);
    default: ;
  endcase
endfunction : apply_out_write


function void ${module_instance_name}_reference_model::commit_straps(
    bit [NUM_GPIOS-1:0] data);
  straps_valid = 1'b1;
  straps_data  = data;
endfunction : commit_straps
