// Copyright zeroRISC Inc.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A reset domain whose reset is produced by the device rather than applied by the testbench.
//
// The device receives five resets and drives the requests behind four of them. Only the
// always-on power-on reset is stimulus a test can apply. The fast, lc and esc resets are
// leaves of it, released through a synchronizer on a clock the device itself gates, or
// they follow a reset the device requested. A component sitting in one of these domains
// still has to stop and recover at its own reset boundary, which is what the inherited
// waits give it, but nothing in the testbench may apply that reset directly.
//
// The inherited wait_reset_deassert() waits for a clock edge with reset released, so a
// component in a domain whose clock is stopped stays held until the clock returns. That is
// the intended behavior here rather than a limitation: the domain is not usable again until
// the device has brought its clock back.
class pwrmgr_derived_rst_domain extends dv_rst_domain;

  `uvm_object_utils(pwrmgr_derived_rst_domain)
  `uvm_object_new

  // Applying a derived reset would overwrite the result the device just produced.
  extern virtual task apply_reset();

  // The clock/reset driver asks this before applying a reset of its own. A derived domain
  // never answers yes, whatever drive state the interface reports, because the component
  // that models the reset owns it instead.
  extern virtual function bit is_driving_reset();
endclass : pwrmgr_derived_rst_domain


task pwrmgr_derived_rst_domain::apply_reset();
  `uvm_fatal(`gfn, {"A derived reset cannot be applied. The always-on power-on reset is the ",
                    "only reset a sequence may drive."})
endtask : apply_reset


function bit pwrmgr_derived_rst_domain::is_driving_reset();
  return 1'b0;
endfunction : is_driving_reset
