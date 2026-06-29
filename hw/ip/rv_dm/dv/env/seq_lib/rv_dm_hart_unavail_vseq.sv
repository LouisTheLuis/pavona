// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rv_dm_hart_unavail_vseq extends rv_dm_base_vseq;
  `uvm_object_utils(rv_dm_hart_unavail_vseq)
  `uvm_object_new

  task check_unavailable(bit req_unavailable);
    uvm_reg_data_t rdata;

    // Set the unavailable pin for the one and only hart to match req_unavailable.
    cfg.rv_dm_vif.cb.unavailable <= req_unavailable;

    fork begin : isolation_fork
      fork
        wait(!cfg.clk_rst_vif.rst_n);

        begin
          // Allow the clocking-block drive to take effect before reading dmstatus.
          cfg.clk_rst_vif.wait_clks(1);

          // Read dmstatus without using mirror(UVM_CHECK). The unavailable input is an external
          // status signal, so the RAL mirror can legitimately be stale at the moment we sample the
          // register.
          //
          // The checks below are still strict: they compare the fields extracted from the DMI read
          // data that just came back from the DUT against the requested unavailable state.
          csr_rd(.ptr(jtag_dmi_ral.dmstatus), .value(rdata));

          // Since there is just one hart, the anyunavail and allunavail fields should both equal
          // the unavailable flag that we have set. Check they do.
          `DV_CHECK_EQ(get_field_val(jtag_dmi_ral.dmstatus.anyunavail, rdata), req_unavailable)
          `DV_CHECK_EQ(get_field_val(jtag_dmi_ral.dmstatus.allunavail, rdata), req_unavailable)
        end
      join_any
      disable fork;
    end join
  endtask

  task body();
    bit reqs[2] = '{1'b0, 1'b1};
    reqs.shuffle();

    foreach (reqs[i]) begin
      check_unavailable(reqs[i]);

      // Wait a short time between the checks, stopping on reset
      fork begin : isolation_fork
        fork
          wait(!cfg.clk_rst_vif.rst_n);
          cfg.clk_rst_vif.wait_clks(10);
        join_any
        disable fork;
      end join
      if (!cfg.clk_rst_vif.rst_n) return;
    end
  endtask

endclass : rv_dm_hart_unavail_vseq
