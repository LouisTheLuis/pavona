// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_keymgr_dpe_sideload_kmac_vseq extends chip_sw_keymgr_dpe_key_derivation_vseq;
  `uvm_object_utils(chip_sw_keymgr_dpe_sideload_kmac_vseq)

  `uvm_object_new

  // The following variables match their SW side equivalents
  localparam int MessageBytes = 4;
  localparam bit [7:0] MsgArr[MessageBytes] = {8'h00, 8'h01, 8'h02, 8'h03};
  localparam string CustomStr = "";
  localparam int DigestBytes = 32;
  localparam int KeyBytes = keymgr_pkg::KeyWidth / 8;

  virtual task body();
    key_shares_t stage_0_key;
    bit [keymgr_pkg::KeyWidth-1:0] sideload_kmac_key;
    bit [7:0] sideload_key_arr[KeyBytes];
    bit [7:0] digest_arr[DigestBytes];

    super.base_body();

    // Wait for keymgr_dpe to become available and thus have consumed the creator root key (aka UDS)
    // into a boot stage 0 key.
    `DV_WAIT(cfg.sw_logger_vif.printed_log == "KeymgrDpe derived boot stage 0 key",
             "Timed out waiting for keymgr_dpe to derive boot stage 0 key",
             20_000_000 /* 20 ms, longer than default because OT needs to come out of SW reset*/)
    begin
      bit valid_found = 1'b0;
      for (int i = 0; i < keymgr_dpe_pkg::DpeNumSlots; i++) begin
        keymgr_dpe_pkg::keymgr_dpe_slot_t slot = get_key_slot(i);
        if (slot.valid) begin
          `DV_CHECK_EQ(valid_found, 1'b0, "Expecting only one valid key slot")
          valid_found = 1'b1;
          `DV_CHECK_EQ(slot.boot_stage, 'd0, "Expecting boot stage to be 0")
          stage_0_key = slot.key;
        end
      end
      `DV_CHECK_EQ(valid_found, 1'b1, "Expecting one valid key slot")
    end

    `DV_WAIT(cfg.sw_logger_vif.printed_log == "KeymgrDpe generated KMAC output from boot stage 0")
    check_generated_output(.key_shares(stage_0_key),
                           // These values must match those passed in SW. (Ideally, we would
                           // backdoor-load them into SW to remove the redundancy, but that's no
                           // immediate priority.)
                           .dest(keymgr_pkg::Kmac),
                           .version('d0),
                           .salt({32'hde919d54, 32'h322288d8, 32'h4bd127c7, 32'h9f89bc56,
                                  32'hb4fb0fdf, 32'h1ca1567b, 32'h13a0e876, 32'hb6521d8f}));

    // Backdoor load the expected result to SW.
    sideload_kmac_key = get_unmasked_key(get_output(keymgr_pkg::Kmac));

    {<< byte {sideload_key_arr}} = sideload_kmac_key;

    c_dpi_kmac128(MsgArr, MessageBytes,
                  sideload_key_arr, KeyBytes,
                  CustomStr,
                  DigestBytes, digest_arr);

    sw_symbol_backdoor_overwrite("sideload_digest_result", digest_arr);
  endtask

endclass : chip_sw_keymgr_dpe_sideload_kmac_vseq
