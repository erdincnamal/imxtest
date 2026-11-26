/*
 * SEGGER Flash Loader for RT1176 FlexSPI1 A1 serial NOR.
 * The on-target ROM API declarations in vendor/ are BSD-3-Clause.
 */
#include <stdint.h>
#include "FlashOS.h"
#include "ufl_rom_api_imxrt117x.h"

#define FLASH_BASE 0x30000000u
#define FLASH_SIZE 0x04000000u
#define FCB_OFFSET 0x400u
#define FCB_SIZE 0x200u
#define FCB_TAG 0x42464346u
#define INSTANCE MIMXRT117X_1st_FLEXSPI_INSTANCE
#define SRC_SRMR (*(volatile uint32_t *)0x40C04004u)
#define FLEXSPI1 ((FLEXSPI_Type *)0x400CC000u)
#define MODE_SDR 0x4D580001u
#define MODE_DDR 0x4D580002u
#define MODE_QSPI 0x4D580003u
/* MX25UW51245G and MX25UM51345G share this RDID. Select DDR byte order by profile. */
#define MACRONIX_OCTAL_ID 0x003A81C2u
#define W25Q512NW_IQ_ID 0x002060EFu
#define LUT(a, p, x, b, q, y) FLEXSPI_LUT_SEQ(a, FLEXSPI_##p##PAD, x, b, FLEXSPI_##q##PAD, y)

#if defined(RT1176_MX25UM51345G)
#if RT1176_FIXED_MODE != MODE_SDR && RT1176_FIXED_MODE != MODE_DDR
#error RT1176_MX25UM51345G requires a fixed Octal mode
#endif
#define MACRONIX_OCTAL_NAME "MX25UM51345G"
#else
#define MACRONIX_OCTAL_NAME "MX25UW51245G"
#endif

#if RT1176_FIXED_MODE == MODE_SDR
#define FLASH_DEVICE_NAME "RT1176 " MACRONIX_OCTAL_NAME " Octal SDR"
#elif RT1176_FIXED_MODE == MODE_DDR
#define FLASH_DEVICE_NAME "RT1176 " MACRONIX_OCTAL_NAME " Octal DDR"
#elif RT1176_FIXED_MODE == MODE_QSPI
#define FLASH_DEVICE_NAME "RT1176 W25Q512NWEIQ Quad SPI"
#elif defined(RT1176_FIXED_MODE)
#error Unsupported RT1176_FIXED_MODE
#else
#define FLASH_DEVICE_NAME "RT1176 FlexSPI1 NOR Winbond Quad / Macronix Octal"
#endif

enum { READ_STATUS = 1, WRITE_ENABLE = 3, ERASE_4K = 5, PROGRAM_4B = 9,
       READ_STATUS2 = 10, SET_READ_PARAMETERS = 11,
       RESET_ENABLE = 12, RESET_MEMORY = 13, READ_ID = 14, WRITE_CR2 = 15 };

/* Persistent between SFL callbacks, outside J-Link's relocatable work RAM. */
typedef struct {
    uint32_t mode;
    uint32_t stage;
    uint32_t detail;
    uint32_t originalReset;
    const flexspi_nor_flash_driver_imxrt117x_t *rom;
    flexspi_nor_config_t config;
} flash_session_t;

#define SESSION ((volatile flash_session_t *)0x20280C00u)
_Static_assert(sizeof(flexspi_nor_config_t) == FCB_SIZE, "RT1176 FCB size");
_Static_assert(sizeof(flash_session_t) <= 0x400, "RT1176 loader session area");

__attribute__((section(".flash_device")))
const struct FlashDevice FlashDevice = {
    FLASH_DRV_VERS, FLASH_DEVICE_NAME, EXTSPI,
    FLASH_BASE, FLASH_SIZE, FLASH_DRV_PAGE_SIZE, 0, 0xFF, 2000, 5000,
    {{FLASH_DRV_SECTOR_SIZE, 0}, {SECTOR_END}}
};

static const flexspi_nor_config_t spiConfig = {
    .memConfig = {
        .tag = FCB_TAG, .version = 0x56010400u, .csHoldTime = 3, .csSetupTime = 3,
        .deviceType = 1, .sflashPadType = 8, .serialClkFreq = kFlexSpiSerialClk_30MHz,
        .sflashA1Size = FLASH_SIZE,
        .lookupTable = {
            [0] = LUT(CMD_SDR, 1, 0x13, RADDR_SDR, 1, 32),
            [1] = LUT(READ_SDR, 1, 4, STOP, 1, 0),
        },
    },
    .pageSize = FLASH_DRV_PAGE_SIZE, .sectorSize = FLASH_DRV_SECTOR_SIZE, .blockSize = 65536
};

static const uint32_t commands[16 * 4] = {
    [4 * READ_STATUS] = LUT(CMD_SDR, 1, 0x05, READ_SDR, 1, 1),
    [4 * WRITE_ENABLE] = LUT(CMD_SDR, 1, 0x06, STOP, 1, 0),
    [4 * ERASE_4K] = LUT(CMD_SDR, 1, 0x21, RADDR_SDR, 1, 32),
    [4 * PROGRAM_4B] = LUT(CMD_SDR, 1, 0x12, RADDR_SDR, 1, 32),
    [4 * PROGRAM_4B + 1] = LUT(WRITE_SDR, 1, 4, STOP, 1, 0),
    [4 * READ_STATUS2] = LUT(CMD_SDR, 1, 0x35, READ_SDR, 1, 1),
    [4 * SET_READ_PARAMETERS] = LUT(CMD_SDR, 1, 0xC0, WRITE_SDR, 1, 1),
    [4 * READ_ID] = LUT(CMD_SDR, 1, 0x9F, READ_SDR, 1, 4),
    [4 * WRITE_CR2] = LUT(CMD_SDR, 1, 0x72, RADDR_SDR, 1, 32),
    [4 * WRITE_CR2 + 1] = LUT(WRITE_SDR, 1, 1, STOP, 1, 0),
};

static const uint32_t ipErrors = FLEXSPI_INTR_IPCMDERR_MASK | FLEXSPI_INTR_IPCMDGE_MASK |
                                 FLEXSPI_INTR_SEQTIMEOUT_MASK;

static void set_lut(uint32_t index, uint32_t count, const uint32_t *entries)
{
    FLEXSPI1->LUTKEY = 0x5AF05AF0u;
    FLEXSPI1->LUTCR = FLEXSPI_LUTCR_UNLOCK_MASK;
    for (uint32_t i = 0; i < count; ++i)
        FLEXSPI1->LUT[index + i] = entries[i];
    FLEXSPI1->LUTKEY = 0x5AF05AF0u;
    FLEXSPI1->LUTCR = FLEXSPI_LUTCR_LOCK_MASK;
}

static void copy_config(const volatile uint8_t *source)
{
    volatile uint8_t *dest = (volatile uint8_t *)&SESSION->config;
    for (uint32_t i = 0; i < FCB_SIZE; ++i)
        dest[i] = source[i];
}

static int wait_flag(uint32_t mask)
{
    for (uint32_t remaining = 100000; remaining; --remaining)
    {
        const uint32_t flags = FLEXSPI1->INTR;
        if (flags & ipErrors)
        {
            SESSION->detail = flags | 0xE0000000u;
            return 0;
        }
        if (flags & mask)
            return 1;
    }
    SESSION->detail = 0xE1000000u | mask;
    return 0;
}

static void begin_command(uint32_t sequence, uint32_t offset, uint32_t length)
{
    /* One 8-byte entry per watermark. ROM transfers may leave a larger watermark. */
    FLEXSPI1->IPRXFCR = FLEXSPI_IPRXFCR_CLRIPRXF_MASK;
    FLEXSPI1->IPTXFCR = FLEXSPI_IPTXFCR_CLRIPTXF_MASK;
    /* Writing IPTXWE commits the next FIFO entry, even before the command starts. */
    FLEXSPI1->INTR = ipErrors | FLEXSPI_INTR_IPCMDDONE_MASK;
    FLEXSPI1->FLSHCR2[0] |= FLEXSPI_FLSHCR2_CLRINSTRPTR_MASK;
    FLEXSPI1->IPCR0 = offset;
    FLEXSPI1->IPCR1 = FLEXSPI_IPCR1_ISEQID(sequence) | length;
}

static int command(uint32_t sequence, uint32_t offset, uint32_t length, uint32_t *readValue)
{
    begin_command(sequence, offset, length);
    FLEXSPI1->IPCMD = 1;
    if (!wait_flag(FLEXSPI_INTR_IPCMDDONE_MASK))
        return 0;
    if (readValue)
        *readValue = FLEXSPI1->RFDR[0];
    return 1;
}

static int transmit(uint32_t sequence, uint32_t offset, uint32_t length, const uint32_t *words)
{
    begin_command(sequence, offset, length);
    if (!wait_flag(FLEXSPI_INTR_IPTXWE_MASK))
        return 0;
    FLEXSPI1->TFDR[0] = words[0];
    FLEXSPI1->TFDR[1] = length > 4 ? words[1] : 0;
    FLEXSPI1->INTR = FLEXSPI_INTR_IPTXWE_MASK;
    FLEXSPI1->IPCMD = 1;
    for (uint32_t i = 8; i < length; i += 8)
    {
        if (!wait_flag(FLEXSPI_INTR_IPTXWE_MASK))
            return 0;
        FLEXSPI1->TFDR[0] = words[i / 4];
        FLEXSPI1->TFDR[1] = words[i / 4 + 1];
        FLEXSPI1->INTR = FLEXSPI_INTR_IPTXWE_MASK;
    }
    return wait_flag(FLEXSPI_INTR_IPCMDDONE_MASK);
}

static int identified(void)
{
    uint32_t id = 0;
    if (!command(READ_ID, 0, 4, &id))
        return 0;
    SESSION->detail = id;
    const uint32_t expected = SESSION->mode == MODE_QSPI ? W25Q512NW_IQ_ID : MACRONIX_OCTAL_ID;
    return (id & 0xFFFFFFu) == expected;
}

static int reset_octal(bool ddr)
{
    static const uint32_t resetDdr[] = {
        LUT(CMD_DDR, 8, 0x66, CMD_DDR, 8, 0x99), 0, 0, 0,
        LUT(CMD_DDR, 8, 0x99, CMD_DDR, 8, 0x66), 0, 0, 0
    };
    static const uint32_t resetSdr[] = {
        LUT(CMD_SDR, 8, 0x66, CMD_SDR, 8, 0x99), 0, 0, 0,
        LUT(CMD_SDR, 8, 0x99, CMD_SDR, 8, 0x66), 0, 0, 0
    };
    set_lut(RESET_ENABLE * 4, 8, ddr ? resetDdr : resetSdr);
    if (!command(RESET_ENABLE, 0, 0, 0) || !command(RESET_MEMORY, 0, 0, 0))
        return 0;
    for (volatile uint32_t delay = 0; delay < 30000; ++delay) { }
    return identified();
}

static int start_spi(void)
{
    copy_config((const uint8_t *)&spiConfig);
    if (SESSION->mode == MODE_QSPI)
        SESSION->config.memConfig.sflashPadType = 4;
    SESSION->stage = 1;
    SESSION->detail = (uint32_t)SESSION->rom->init(INSTANCE, (flexspi_nor_config_t *)&SESSION->config);
    if (SESSION->detail != 0)
        return 0;
    set_lut(4, 60, &commands[4]);
    SESSION->stage = 2;
    if (identified())
        return 1;
    if (SESSION->mode == MODE_QSPI)
        return 0;
    SESSION->stage = 3;
    if (reset_octal(false))
        return 1;
    SESSION->stage = 4;
    return reset_octal(true);
}

static int write_enabled(void)
{
    uint32_t status = 0;
    if (!command(WRITE_ENABLE, 0, 0, 0) || !command(READ_STATUS, 0, 1, &status))
        return 0;
    SESSION->detail = status;
    return (status & 3u) == 2u;
}

static int wait_write_complete(void)
{
    for (uint32_t remaining = 6000; remaining; --remaining)
    {
        uint32_t status = 0;
        if (!command(READ_STATUS, 0, 1, &status))
            return 0;
        if ((status & 3u) == 0)
            return 1;
        SESSION->detail = status;
        if ((status & 1u) == 0)
            return 0;
        for (volatile uint32_t delay = 0; delay < 2000; ++delay) { }
    }
    return 0;
}

static int refresh_flash_map(void)
{
    FLEXSPI1->MCR0 |= FLEXSPI_MCR0_SWRESET_MASK;
    for (uint32_t remaining = 100000; remaining; --remaining)
        if ((FLEXSPI1->MCR0 & FLEXSPI_MCR0_SWRESET_MASK) == 0)
            return 1;
    SESSION->detail = 0xE2000000u;
    return 0;
}

int SEGGER_FL_Prepare(uint32_t p0, uint32_t p1, uint32_t p2)
{
    (void)p0; (void)p1; (void)p2;
#ifdef RT1176_FIXED_MODE
    SESSION->mode = RT1176_FIXED_MODE;
#else
    if (SESSION->mode != MODE_SDR && SESSION->mode != MODE_DDR && SESSION->mode != MODE_QSPI)
        return -1;
#endif
    SESSION->stage = 0;
    SESSION->detail = 0;
    switch (MEM_ReadU32(0x40C84800u))
    {
        case 0x001170A0u: SESSION->rom = g_bootloaderTree_imxrt117x_a0->flexspiNorDriver; break;
        case 0x001170B0u:
        case 0x001170C0u: SESSION->rom = g_bootloaderTree_imxrt117x_b0c0->flexspiNorDriver; break;
        default: return -2;
    }
    SESSION->originalReset = SRC_SRMR;
    SRC_SRMR = SESSION->originalReset | 0x3FFu;
    if (!start_spi())
    {
        SRC_SRMR = SESSION->originalReset;
        return -3;
    }
    SESSION->stage = 5;
    return 0;
}

static int restore_quad(flexspi_mem_config_t *config)
{
    uint32_t status = 0;
    if (!command(READ_STATUS2, 0, 1, &status))
        return 0;
    const uint32_t seq = config->configCmdSeqs[0].seqId;
    const uint32_t arg = config->configCmdArgs[0];
    const bool validSequence = seq < 16 && config->configCmdSeqs[0].seqNum == 1 &&
                               config->configCmdSeqs[1].seqNum == 0 && config->configCmdSeqs[2].seqNum == 0 &&
                               config->lookupTable[4 * seq] == commands[4 * SET_READ_PARAMETERS] &&
                               config->lookupTable[4 * seq + 1] == 0 && arg <= 0xFF;
    if ((status & 2u) == 0 || config->deviceModeCfgEnable || (config->configCmdEnable && !validSequence))
    {
        SESSION->detail = 0xE3000000u | (status & 0xFF);
        return 0;
    }
    if (config->configCmdEnable && !transmit(SET_READ_PARAMETERS, 0, 1, &arg))
        return 0;
    config->configCmdEnable = 0;
    return 1;
}

static inline bool uses_data_swap(void)
{
#if defined(RT1176_MX25UM51345G)
    /* The MX25UM51345G uses byte order in both STR and DTR. */
    return false;
#elif defined(RT1176_FIXED_MODE)
    return RT1176_FIXED_MODE == MODE_DDR;
#else
    return SESSION->mode == MODE_DDR;
#endif
}

int SEGGER_FL_Restore(uint32_t p0, uint32_t p1, uint32_t p2)
{
    (void)p0; (void)p1; (void)p2;
    flash_session_t *session = (flash_session_t *)SESSION;
    copy_config((volatile const uint8_t *)(FLASH_BASE + FCB_OFFSET));
    const uint32_t arg = session->config.memConfig.deviceModeArg;
    int result = 0;
    const uint32_t pads = session->config.memConfig.sflashPadType;
    if (session->config.memConfig.tag == FCB_TAG && session->config.memConfig.sflashA1Size == FLASH_SIZE)
    {
        SESSION->stage = 6;
#ifdef RT1176_FIXED_MODE
        if (session->config.pageSize != FLASH_DRV_PAGE_SIZE ||
            session->config.sectorSize != FLASH_DRV_SECTOR_SIZE ||
            session->config.isDataOrderSwapped != uses_data_swap())
        {
            SESSION->detail = 0xE4000000u;
            SESSION->stage = 8;
            SRC_SRMR = SESSION->originalReset;
            return -1;
        }
#endif
        const bool modeChanged = session->mode == MODE_QSPI
                                     ? pads == 4 && restore_quad(&session->config.memConfig)
                                     : pads == 8 && (arg == 1 || arg == 2) && write_enabled() &&
                                           transmit(WRITE_CR2, 0, 1, &arg);
        if (modeChanged)
        {
            session->config.memConfig.deviceModeCfgEnable = 0;
            SESSION->detail = (uint32_t)session->rom->init(INSTANCE, &session->config);
            result = SESSION->detail == 0 ? 0 : -1;
        }
        else
            result = -1;
    }
    SRC_SRMR = SESSION->originalReset;
    SESSION->stage = result == 0 ? 7 : 8;
    return result;
}

#ifdef RT1176_FIXED_MODE
static uint32_t fcb_word(const uint8_t *data)
{
    return data[0] | ((uint32_t)data[1] << 8) | ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static bool fcb_matches(const uint8_t *data, uint32_t length)
{
    /* Flash programs that do not contain an FCB can still use the same bank. */
    if (fcb_word(data) != FCB_TAG)
        return true;
    const bool ddr = (data[0x40] & 0x40u) != 0;
    const uint32_t modeArg = fcb_word(data + 0x18);
    if (ddr != (RT1176_FIXED_MODE == MODE_DDR) || fcb_word(data + 0x50) != FLASH_SIZE)
        return false;
    if (length >= FCB_SIZE &&
        (fcb_word(data + 0x1c0) != FLASH_DRV_PAGE_SIZE ||
         fcb_word(data + 0x1c4) != FLASH_DRV_SECTOR_SIZE ||
         data[0x1ca] != uses_data_swap()))
        return false;
    if (RT1176_FIXED_MODE == MODE_QSPI)
        return data[0x45] == 4 && data[0x10] == 0;
    return data[0x45] == 8 && data[0x10] == 1 &&
           modeArg == (RT1176_FIXED_MODE == MODE_DDR ? 2u : 1u);
}
#endif

static uint32_t flash_offset(uint32_t address)
{
    return address >= FLASH_BASE ? address - FLASH_BASE : address;
}

static int valid_range(uint32_t offset, uint32_t length)
{
    return offset < FLASH_SIZE && length <= FLASH_SIZE - offset;
}

static uint32_t physical_offset(uint32_t offset, bool swap)
{
    /* Always keep the FCB in SPI order, including for word-mode DDR flash. */
    return swap && (offset < FCB_OFFSET || offset >= FCB_OFFSET + FCB_SIZE) ? offset ^ 1u : offset;
}

int SEGGER_FL_Erase(uint32_t address, uint32_t sectorIndex, uint32_t count)
{
    uint32_t offset = flash_offset(address);
    if (count > FLASH_SIZE / FLASH_DRV_SECTOR_SIZE || offset % FLASH_DRV_SECTOR_SIZE ||
        offset / FLASH_DRV_SECTOR_SIZE != sectorIndex || !valid_range(offset, count * FLASH_DRV_SECTOR_SIZE))
        return 1;
    while (count--)
    {
        SESSION->stage = 0x10000u | (offset / FLASH_DRV_SECTOR_SIZE);
        if (!write_enabled() || !command(ERASE_4K, offset, 0, 0) || !wait_write_complete())
            return 1;
        offset += FLASH_DRV_SECTOR_SIZE;
    }
    return refresh_flash_map() ? 0 : 1;
}

int SEGGER_FL_Read(uint32_t address, uint32_t length, uint8_t *dest)
{
    const uint32_t offset = flash_offset(address);
    if (!valid_range(offset, length))
        return -1;
    const bool swap = uses_data_swap();
    const volatile uint8_t *flash = (const volatile uint8_t *)FLASH_BASE;
    for (uint32_t i = 0; i < length; ++i)
        dest[i] = flash[physical_offset(offset + i, swap)];
    return (int)length;
}

uint32_t SEGGER_FL_Verify(uint32_t address, uint32_t length, uint8_t *data)
{
    const uint32_t offset = flash_offset(address);
    if (!valid_range(offset, length))
        return address;
    const bool swap = uses_data_swap();
    const volatile uint8_t *flash = (const volatile uint8_t *)FLASH_BASE;
    for (uint32_t i = 0; i < length; ++i)
        if (data[i] != flash[physical_offset(offset + i, swap)])
            return address + i;
    return address + length;
}

int SEGGER_FL_Program(uint32_t address, uint32_t length, uint8_t *data)
{
    uint32_t offset = flash_offset(address);
    if (offset % FLASH_DRV_PAGE_SIZE || length % FLASH_DRV_PAGE_SIZE || !valid_range(offset, length))
        return 1;
    const bool swap = uses_data_swap();
    const uint32_t end = offset + length;
#ifdef RT1176_FIXED_MODE
    if (offset <= FCB_OFFSET && end > FCB_OFFSET &&
        !fcb_matches(data + FCB_OFFSET - offset, end - FCB_OFFSET))
    {
        SESSION->stage = 0x40000u | (FCB_OFFSET / FLASH_DRV_PAGE_SIZE);
        SESSION->detail = 0xE4000000u;
        SRC_SRMR = SESSION->originalReset;
        return 1;
    }
#endif
    uint32_t page[FLASH_DRV_PAGE_SIZE / sizeof(uint32_t)];
    uint8_t *bytes = (uint8_t *)page;
    while (offset < end)
    {
        SESSION->stage = 0x40000u | (offset / FLASH_DRV_PAGE_SIZE);
        for (uint32_t i = 0; i < FLASH_DRV_PAGE_SIZE; ++i)
            bytes[physical_offset(offset + i, swap) - offset] = data[i];
        if (!write_enabled() || !transmit(PROGRAM_4B, offset, FLASH_DRV_PAGE_SIZE, page) ||
            !wait_write_complete() || !refresh_flash_map())
            return 1;
        const uint32_t verified = SEGGER_FL_Verify(offset, FLASH_DRV_PAGE_SIZE, data);
        if (verified != offset + FLASH_DRV_PAGE_SIZE)
        {
            SESSION->detail = FLASH_BASE + verified;
            return 1;
        }
        offset += FLASH_DRV_PAGE_SIZE;
        data += FLASH_DRV_PAGE_SIZE;
    }
    return 2;
}
