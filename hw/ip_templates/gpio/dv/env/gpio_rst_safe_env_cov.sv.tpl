// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Coverage for the reset-safe environment.
//
// Deliberately separate from ${module_instance_name}_env_cov. The legacy groups are sampled from the
// legacy scoreboard's signal watching loops, at points where nothing has been checked, so
// carrying them into the reset-safe report would credit this path with coverage it has not
// earned. The legacy class stays in use by the legacy environment and is not deleted.
//
// The groups are added once the checker they are sampled from exists. A coverpoint written
// before that records that a value was seen rather than that a result was checked.
class ${module_instance_name}_rst_safe_env_cov extends cip_base_env_cov #(
    .CFG_T(${module_instance_name}_env_cfg)
  );
  `uvm_component_utils(${module_instance_name}_rst_safe_env_cov)

  // How long a pin held its value before changing, crossed with whether the filter was
  // enabled on it. The filter passes a change only after the input has been stable for the
  // whole window, so the two sides of that boundary are the cases worth separating, and the
  // cross with the filter enable is what says both were reached on the same pin.
  //
  // Sampled from the scoreboard, after the filtered input for the cycle has been compared
  // against the model. A sample taken before that would record that a value was seen rather
  // than that a result was checked.
  covergroup pins_stable_period_and_filter_cg with function sample(int unsigned pin,
                                                                   int unsigned stable_cycles,
                                                                   bit pin_value,
                                                                   bit filter_en);
    cp_pins: coverpoint pin {
      bins all_gpio_pins[] = {[0:NUM_GPIOS-1]};
    }
    cp_stable_cycles: coverpoint stable_cycles {
      bins one_to_filter_cycles_minus_1[] = {[1:FILTER_CYCLES - 1]};
      bins filter_cycles_or_more          = {[FILTER_CYCLES:$]};
    }
    cp_pin_value: coverpoint pin_value;
    cp_filter_en: coverpoint filter_en;
    cp_cross: cross cp_pins, cp_stable_cycles, cp_pin_value, cp_filter_en;
  endgroup : pins_stable_period_and_filter_cg

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pins_stable_period_and_filter_cg = new();
  endfunction : new

endclass : ${module_instance_name}_rst_safe_env_cov
