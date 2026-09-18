// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_keymgr_dpe_sideload_aes_vseq extends chip_sw_keymgr_dpe_key_derivation_vseq;
  `uvm_object_utils(chip_sw_keymgr_dpe_sideload_aes_vseq)

  `uvm_object_new

  // Plaintext 16B block (transposed) matching input at the SW test: `0x00112233445566778899aabbccddeeff`
  // Refer to `hw/ip/aes/rtl/aes_cipher_core.sv` for mapping plaintext input to the AES core.
  localparam bit [3:0][3:0][7:0] PlainText = {
             32'hffbb7733,
             32'heeaa6622,
             32'hdd995511,
             32'hcc884400
  };


  virtual task body();
    begin
      key_shares_t stage_0_key;
      bit [3:0][3:0][7:0] ciphertext;
      bit [3:0][3:0][7:0] ciphertext_transposed;
      bit [7:0] digest [16];
      bit [7:0] digest_rev [16];
      bit [keymgr_pkg::KeyWidth-1:0] sideload_aes_key;
      bit [keymgr_pkg::KeyWidth-1:0] sideload_aes_key_rev;

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

      `DV_WAIT(cfg.sw_logger_vif.printed_log == "KeymgrDpe generated AES output from boot stage 0")
      check_generated_output(.key_shares(stage_0_key),
                            // These values must match those passed in SW. (Ideally, we would
                            // backdoor-load them into SW to remove the redundancy, but that's no
                            // immediate priority.)
                            .dest(keymgr_pkg::Aes),
                            .version('d0),
                            .salt({32'hde919d54, 32'h322288d8, 32'h4bd127c7, 32'h9f89bc56,
                                    32'hb4fb0fdf, 32'h1ca1567b, 32'h13a0e876, 32'hb6521d8f}));

      // Fetch the AES sideload key from keymgr_dpe and test it with AES.
      sideload_aes_key = get_unmasked_key(get_output(keymgr_pkg::Aes));

      // Compute AES block encryption (C model) with above unmasked key.
      aes_model_dpi_pkg::c_dpi_aes_crypt_block(1'b0, 1'b0, 6'b00_0001, 128'h0, 3'b100,
                            sideload_aes_key,
                            PlainText,
                            ciphertext);

      // Transpose, unpack and reverse byte order of ciphertext to match digest from AES HW core.
      ciphertext_transposed = aes_pkg::aes_transpose(ciphertext);
      {>>{digest}} = ciphertext_transposed;
      {<< byte {digest_rev}} = digest;

      // Transfer the expected AES digest to the C test via the backdoor SW symbol.
      sw_symbol_backdoor_overwrite("kAESDigest", digest_rev);

      // Reverse byte order of key to match the AES NIST.FIPS.197 standard.
      {<< byte {sideload_aes_key_rev}} = sideload_aes_key;

      `uvm_info(`gfn, $sformatf("AES Plaintext (C model): 0x%0h", PlainText), UVM_LOW)
      `uvm_info(`gfn, $sformatf("AES Ciphertext (C model): 0x%0h", ciphertext_transposed), UVM_LOW)
      `uvm_info(`gfn, $sformatf("AES Sideload Key0x%0h", sideload_aes_key_rev), UVM_LOW)
    end
  endtask

endclass : chip_sw_keymgr_dpe_sideload_aes_vseq
