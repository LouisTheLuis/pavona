// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "hw/top/dt/otp_ctrl.h"
#include "hw/top/dt/rstmgr.h"
#include "hw/top/dt/sram_ctrl.h"
#include "sw/device/lib/arch/device.h"
#include "sw/device/lib/base/abs_mmio.h"
#include "sw/device/lib/base/mmio.h"
#include "sw/device/lib/dif/dif_base.h"
#include "sw/device/lib/dif/dif_otp_ctrl.h"
#include "sw/device/lib/dif/dif_rstmgr.h"
#include "sw/device/lib/dif/dif_sram_ctrl.h"
#include "sw/device/lib/runtime/hart.h"
#include "sw/device/lib/runtime/irq.h"
#include "sw/device/lib/runtime/log.h"
#include "sw/device/lib/testing/otp_ctrl_testutils.h"
#include "sw/device/lib/testing/rand_testutils.h"
#include "sw/device/lib/testing/test_framework/check.h"
#include "sw/device/lib/testing/test_framework/ottf_main.h"
#include "sw/device/lib/testing/test_framework/status.h"

#include "hw/top/otp_ctrl_regs.h"

#if defined(OPENTITAN_IS_EGRET)
#include "hw/top/dt/flash_ctrl.h"
#include "sw/device/lib/dif/dif_flash_ctrl.h"
#include "sw/device/lib/testing/flash_ctrl_testutils.h"

#include "hw/top/flash_ctrl_regs.h"
#endif

static dif_rstmgr_t rstmgr;
static_assert(kDtRstmgrCount >= 1, "this test expects a rstmgr");
static dif_otp_ctrl_t otp_ctrl;
static_assert(kDtOtpCtrlCount >= 1, "This test requires an otp_ctrl");
static dif_sram_ctrl_t sram_ctrls[kDtSramCtrlCount];
static_assert(kDtSramCtrlCount >= 1, "This test requires an sram_ctrl");

#if defined(OPENTITAN_IS_EGRET)
static dif_flash_ctrl_state_t flash_ctrl;
static_assert(kDtFlashCtrlCount >= 1, "This test requires a flash_ctrl");
const enum {
  kFlashPageSize = FLASH_CTRL_PARAM_BYTES_PER_PAGE,
  kFlashStartAddr = TOP_EGRET_FLASH_CTRL_MEM_BASE_ADDR,
  kFlashMpRegions = FLASH_CTRL_PARAM_NUM_REGIONS
};
#endif

static const dif_sram_ctrl_status_t kSramStatusErrMask =
    kDifSramCtrlStatusBusIntegErr | kDifSramCtrlStatusInitErr |
    kDifSramCtrlStatusEscalated;

static void init_sram_difs(void) {
  // Initialize Srams
  for (dt_sram_ctrl_t sc = (dt_sram_ctrl_t)0; sc < kDtSramCtrlCount; ++sc) {
    CHECK_DIF_OK(dif_sram_ctrl_init_from_dt(sc, &sram_ctrls[sc]));
  }
}

static void request_sram_scr_keys(void) {
  for (dt_sram_ctrl_t sc = (dt_sram_ctrl_t)0; sc < kDtSramCtrlCount; ++sc) {
    CHECK_DIF_OK(dif_sram_ctrl_scramble(&sram_ctrls[sc]));
  }
}

static void check_srams_seed_status(bool is_seed_injected) {
  // Check Status registers for Srams to see if their scrambling key seeds are
  // valid
  for (dt_sram_ctrl_t sc = (dt_sram_ctrl_t)0; sc < kDtSramCtrlCount; ++sc) {
    dif_sram_ctrl_status_bitfield_t sram_status;
    CHECK_DIF_OK(dif_sram_ctrl_get_status(&sram_ctrls[sc], &sram_status));
    CHECK((sram_status & kSramStatusErrMask) == 0x0,
          "Sram_ctrl %d status error bits set; status = %08x.", (int)sc,
          sram_status);
    if (is_seed_injected) {
      CHECK((sram_status & kDifSramCtrlStatusScrKeySeedValid) == 0x1,
            "OTP Sram partition is locked. Sram_ctrl %d should have a valid "
            "scrambling key seed; status = %08x.",
            (int)sc, sram_status);
    } else {
      CHECK((sram_status & kDifSramCtrlStatusScrKeySeedValid) == 0x0,
            "OTP Sram partition is unlocked. Sram_ctrl %d should have an "
            "invalid scrambling key seed; status = %08x.",
            (int)sc, sram_status);
    }
  }
}

static void randomize_otp_seed_key(uint32_t key_offset, uint32_t key_size) {
  for (uint32_t i = 0; i < key_size; i += sizeof(uint64_t)) {
    uint64_t rand_val =
        (uint64_t)rand_testutils_gen32() << 32 | rand_testutils_gen32();
    CHECK_DIF_OK(dif_otp_ctrl_dai_program64(&otp_ctrl, kOtpPartitionSecret1,
                                            key_offset + i, rand_val));
    CHECK_STATUS_OK(otp_ctrl_testutils_wait_for_dai(&otp_ctrl));
  };
}

OTTF_DEFINE_TEST_CONFIG();

#if defined(OPENTITAN_IS_EGRET)
// Expected data for the scramble seed, directly backdoor loaded by the
// test environment.  The data has to be backdoor loaded because the
// life cycle state used in this test does not permit the isolated
// partition to be written.
OT_SET_BSS_SECTION(".non_volatile_scratch", uint32_t kIsoPartExpData[16];)
static void check_iso_data(dif_flash_ctrl_state_t *flash_ctrl) {
  // Disable scramble on expected data page
  uint32_t exp_data_addr = (uint32_t)&kIsoPartExpData;
  uint32_t base_page = (exp_data_addr - kFlashStartAddr) / kFlashPageSize;
  dif_flash_ctrl_region_properties_t exp_page = {
      .rd_en = kMultiBitBool4True,
      .prog_en = kMultiBitBool4False,
      .erase_en = kMultiBitBool4False,
      .scramble_en = kMultiBitBool4False,
      .ecc_en = kMultiBitBool4False,
      .high_endurance_en = kMultiBitBool4False};
  uint32_t addr = 0;
  CHECK_STATUS_OK(flash_ctrl_testutils_data_region_setup_properties(
      flash_ctrl, base_page, /*data_region=*/kFlashMpRegions - 1,
      /*region_size=*/1, exp_page, &addr));

  // Double check that the region address covers the area we care about.
  CHECK((exp_data_addr >= (addr + kFlashStartAddr)) &&
        (exp_data_addr < (addr + kFlashPageSize + kFlashStartAddr)));

  // Enable access to isolated page.
  dif_flash_ctrl_region_properties_t iso_page = {
      .rd_en = kMultiBitBool4True,
      .prog_en = kMultiBitBool4False,
      .erase_en = kMultiBitBool4False,
      .scramble_en = kMultiBitBool4False,
      .ecc_en = kMultiBitBool4False,
      .high_endurance_en = kMultiBitBool4False};

  CHECK_STATUS_OK(flash_ctrl_testutils_info_region_setup_properties(
      flash_ctrl, /*page_id=*/3,
      /*bank=*/0, /*partition_id=*/0, iso_page, &addr));

  uint32_t read_data[16];
  CHECK_STATUS_OK(flash_ctrl_testutils_read(
      flash_ctrl, addr, /*partition_id=*/0, read_data,
      kDifFlashCtrlPartitionTypeInfo, ARRAYSIZE(read_data), 0));

  CHECK_ARRAYS_EQ(kIsoPartExpData, read_data, ARRAYSIZE(read_data),
                  "Isolated info page data mismatch.");
};
#endif

bool test_main(void) {
  CHECK_DIF_OK(dif_rstmgr_init_from_dt(kDtRstmgrAon, &rstmgr));

  CHECK_DIF_OK(dif_otp_ctrl_init_from_dt(kDtOtpCtrl, &otp_ctrl));

#if defined(OPENTITAN_IS_EGRET)
  CHECK_DIF_OK(dif_flash_ctrl_init_state_from_dt(&flash_ctrl, kDtFlashCtrl));
#endif

  init_sram_difs();

  bool secret1_locked = false;
  CHECK_DIF_OK(dif_otp_ctrl_is_digest_computed(&otp_ctrl, kOtpPartitionSecret1,
                                               &secret1_locked));

  if (!secret1_locked) {
    LOG_INFO("Powered up for the first time, program and lock otp");

    // TODO (#631) Correctly test sram's seed keys, if this test is to be
    // re-introduced on dragonfly

    // Ensure sram seed keys aren't valid before locking partition
    // request_sram_scr_keys();
    // check_srams_seed_status(false);

#if defined(OPENTITAN_IS_EGRET)
    // Check Isolated partition data is correct prior to enabling scrambling.
    check_iso_data(&flash_ctrl);
#endif

    // Populate the scramble seeds in otp.
    rand_testutils_reseed();

// The secret partition must be 64b aligned...for some reason. Figure out later.
// Program the flash/sram scrambling keys in otp's secret1 partition
#if defined(OPENTITAN_IS_EGRET)
    const uint32_t kFlashAddrKeyOffset =
        OTP_CTRL_PARAM_FLASH_ADDR_KEY_SEED_OFFSET -
        OTP_CTRL_PARAM_SECRET1_OFFSET;
    const uint32_t kFlashDataKeyOffset =
        OTP_CTRL_PARAM_FLASH_DATA_KEY_SEED_OFFSET -
        OTP_CTRL_PARAM_SECRET1_OFFSET;
    randomize_otp_seed_key(kFlashAddrKeyOffset,
                           OTP_CTRL_PARAM_FLASH_ADDR_KEY_SEED_SIZE);
    randomize_otp_seed_key(kFlashDataKeyOffset,
                           OTP_CTRL_PARAM_FLASH_DATA_KEY_SEED_SIZE);
#endif
    const uint32_t kSramDataKeyOffset =
        OTP_CTRL_PARAM_SRAM_DATA_KEY_SEED_OFFSET -
        OTP_CTRL_PARAM_SECRET1_OFFSET;
    randomize_otp_seed_key(kSramDataKeyOffset,
                           OTP_CTRL_PARAM_SRAM_DATA_KEY_SEED_SIZE);

    // Lock the secret1 partition.
    CHECK_STATUS_OK(
        otp_ctrl_testutils_lock_partition(&otp_ctrl, kOtpPartitionSecret1, 0));

#if defined(OPENTITAN_IS_EGRET)
    // Inform rom to setup scramble next round.
    // Scrambling is enabled by default for Srams
    uint32_t otp_val = 0;
    otp_val = bitfield_field32_write(
        otp_val, FLASH_CTRL_DEFAULT_REGION_SCRAMBLE_EN_FIELD,
        kMultiBitBool4True);
    CHECK_DIF_OK(dif_otp_ctrl_dai_program32(
        &otp_ctrl, kOtpPartitionCreatorSwCfg,
        (OTP_CTRL_PARAM_CREATOR_SW_CFG_FLASH_DATA_DEFAULT_CFG_OFFSET -
         OTP_CTRL_PARAM_CREATOR_SW_CFG_OFFSET),
        otp_val));
    CHECK_STATUS_OK(otp_ctrl_testutils_wait_for_dai(&otp_ctrl));
#endif

    // Check to see if there are any otp_ctrl errors.
    dif_otp_ctrl_status_t status;
    CHECK_DIF_OK(dif_otp_ctrl_get_status(&otp_ctrl, &status));

    // There should not have been any errors.
    // The only bit that should be asserted is the IDLE bit.
    LOG_INFO("otp_ctrl status: 0x%x", status.codes);
    CHECK(status.codes == 1 << OTP_CTRL_STATUS_DAI_IDLE_BIT);

    // Reset the device.
    LOG_INFO("Completed first phase, wait for reset");
    CHECK_DIF_OK(dif_rstmgr_software_device_reset(&rstmgr));
    wait_for_interrupt();
    return false;
  } else if (secret1_locked) {
#if defined(OPENTITAN_IS_EGRET)
    // Check Isolated partition data is correct after scramble enabled.
    check_iso_data(&flash_ctrl);
#endif
    // TODO (#631) Correctly test sram's seed keys, if this test is to be
    // re-introduced on dragonfly

    // Ensure sram seed keys are valid after locking partition
    // request_sram_scr_keys();
    // check_srams_seed_status(true);

    LOG_INFO("Hello World");
    return true;
  }
  return false;
}
