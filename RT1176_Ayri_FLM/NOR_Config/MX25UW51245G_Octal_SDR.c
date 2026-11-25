/*
 * Copyright 2018-2022 NXP
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "evkbmimxrt1170_flexspi_nor_config.h"

/* Component ID definition, used by tools. */
#ifndef FSL_COMPONENT_ID
#define FSL_COMPONENT_ID "platform.drivers.xip_board"
#endif

/*******************************************************************************
 * Code
 ******************************************************************************/
#if defined(XIP_BOOT_HEADER_ENABLE) && (XIP_BOOT_HEADER_ENABLE == 1)
#if defined(__CC_ARM) || defined(__ARMCC_VERSION) || defined(__GNUC__)
__attribute__((section(".boot_hdr.conf"), used))
#elif defined(__ICCARM__)
#pragma location = ".boot_hdr.conf"
#endif
/* If your linker expects a different symbol/section, preserve that mapping. */
const flexspi_nor_config_t octalflash_config = {
    .memConfig = {
        .tag                  = FLEXSPI_CFG_BLK_TAG,
        .version              = FLEXSPI_CFG_BLK_VERSION,
        .readSampleClkSrc     = kFlexSPIReadSampleClk_LoopbackInternally,
        .csHoldTime           = 3u,
        .csSetupTime          = 3u,

        /* SPI -> Octal SDR through volatile CR2[1:0] at address 0x00000000. */
        .deviceModeCfgEnable  = 1u,
        .deviceModeType       = kDeviceConfigCmdType_Spi2Xpi,
        .waitTimeCfgCommands  = 1u,
        .deviceModeSeq        = {
            .seqNum           = 1u,
            .seqId            = 6u,
            .reserved         = 0u,
        },
        .deviceModeArg        = 0x01u, /* CR2 DOPI/SOPI = binary 01 */

        .controllerMiscOption =
            (1u << kFlexSpiMiscOffset_SafeConfigFreqEnable),
        .deviceType           = kFlexSpiDeviceType_SerialNOR,
        .sflashPadType        = kSerialFlash_8Pads,
        .serialClkFreq        = kFlexSpiSerialClk_30MHz,
        .sflashA1Size         = 64ul * 1024u * 1024u,

        /* Zero delay to match the supplied SDK struct and board config.
           Verify/tune against scope measurements and the actual SDK type. */
        .dataValidTime        = { [0] = 0u },
        .busyOffset           = 0u, /* RDSR WIP bit 0, 1 means busy */
        .busyBitPolarity      = 0u,

        .lookupTable = {
            /* 0: Read. Octal STR uses 20 dummy SCLK. */
        		    [0 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,   FLEXSPI_8PAD, 0xEC, CMD_SDR,   FLEXSPI_8PAD, 0x13),
        		    [0 + 1] = FLEXSPI_LUT_SEQ(RADDR_SDR, FLEXSPI_8PAD, 0x20, DUMMY_SDR, FLEXSPI_8PAD, 0x14),
        		    [0 + 2] = FLEXSPI_LUT_SEQ(READ_SDR,  FLEXSPI_8PAD, 0x04, STOP,      FLEXSPI_1PAD, 0x00),

        		    /* 1: Read Status (SPI, 05h) */
        		    [4 * 1 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,  FLEXSPI_1PAD, 0x05, READ_SDR, FLEXSPI_1PAD, 0x04),

        		    /* 2: Read Status (OPI SDR, 4 address bytes and 4 dummy SCLK). */
        		    [4 * 2 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,  FLEXSPI_8PAD, 0x05, CMD_SDR, FLEXSPI_8PAD, 0xFA),
    		    [4 * 2 + 1] = FLEXSPI_LUT_SEQ(RADDR_SDR, FLEXSPI_8PAD, 0x20, DUMMY_SDR, FLEXSPI_8PAD, 0x04),
        		    [4 * 2 + 2] = FLEXSPI_LUT_SEQ(READ_SDR,  FLEXSPI_8PAD, 0x04, STOP,      FLEXSPI_1PAD, 0x00),

        		    /* 3: Write Enable (SPI, 06h) */
        		    [4 * 3 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_1PAD, 0x06, STOP,    FLEXSPI_1PAD, 0x00),

        		    /* 4: Write Enable (OPI SDR, 06h + F9h) */
        		    [4 * 4 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_8PAD, 0x06, CMD_SDR, FLEXSPI_8PAD, 0xF9),

        		    /* 5: Sector Erase (21h + DEh + 32-bit address) */
        		    [4 * 5 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,   FLEXSPI_8PAD, 0x21, CMD_SDR, FLEXSPI_8PAD, 0xDE),
        		    [4 * 5 + 1] = FLEXSPI_LUT_SEQ(RADDR_SDR, FLEXSPI_8PAD, 0x20, STOP,    FLEXSPI_1PAD, 0x00),

        		    /* 6: Configuration Register 2 Write (72h + address 0 + data 0x01). */
        		    [4 * 6 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_1PAD, 0x72, CMD_SDR,   FLEXSPI_1PAD, 0x00),
        		    [4 * 6 + 1] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_1PAD, 0x00, CMD_SDR,   FLEXSPI_1PAD, 0x00),
        		    [4 * 6 + 2] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_1PAD, 0x00, WRITE_SDR, FLEXSPI_1PAD, 0x01),

        		    /* 7: Ekran goruntulerinde tanimli degil */

        		    /* 8: Block Erase (DCh + 23h + 32-bit address) */
        		    [4 * 8 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,   FLEXSPI_8PAD, 0xDC, CMD_SDR, FLEXSPI_8PAD, 0x23),
        		    [4 * 8 + 1] = FLEXSPI_LUT_SEQ(RADDR_SDR, FLEXSPI_8PAD, 0x20, STOP,    FLEXSPI_1PAD, 0x00),

        		    /* 9: Page Program (12h + EDh + 32-bit address + write data) */
        		    [4 * 9 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR,   FLEXSPI_8PAD, 0x12, CMD_SDR,   FLEXSPI_8PAD, 0xED),
        		    [4 * 9 + 1] = FLEXSPI_LUT_SEQ(RADDR_SDR, FLEXSPI_8PAD, 0x20, WRITE_SDR, FLEXSPI_8PAD, 0x04),

        		    /* 10: Ekran goruntulerinde tanimli degil */

        		    /* 11: Chip Erase (60h + 9Fh) */
        		    [4 * 11 + 0] = FLEXSPI_LUT_SEQ(CMD_SDR, FLEXSPI_8PAD, 0x60, CMD_SDR, FLEXSPI_8PAD, 0x9F),
        },
    },

    .pageSize           = 256u,
    .sectorSize         = 4u * 1024u,
    .blockSize          = 64u * 1024u,
    .isUniformBlockSize = false,
    .isDataOrderSwapped = false,
    .serialNorType      = 2u,
    .FlashStateCtx      = 0x07008100u, /* SPI after POR, SOPI after init, Macronix reset sequence. */
};
#endif /* XIP_BOOT_HEADER_ENABLE */
