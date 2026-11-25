# RT1176 ayrı J-Link flash loader’ları

Her FLM tek bir flash ve açılış modu için derlendi. Dördüncü kart ve flash kombinasyonu belirlendiğinde aynı klasöre eklenebilir.

| Kart ve mod | J-Link Device alanı | NOR config örneği |
|---|---|---|
| Custom, Macronix MX25UW51245G Octal SDR | `MIMXRT1176B_MX25UW51245G_SDR_M7` | [MX25UW51245G_Octal_SDR.c](NOR_Config/MX25UW51245G_Octal_SDR.c) |
| Custom, Macronix MX25UW51245G Octal DDR | `MIMXRT1176B_MX25UW51245G_DDR_M7` | [MX25UW51245G_Octal_DDR.c](NOR_Config/MX25UW51245G_Octal_DDR.c) |
| EVKB, Winbond W25Q512NWEIQ QSPI | `MIMXRT1176_EVKB_W25Q512NWEIQ_QSPI_M7` | [W25Q512NWEIQ_EVKB_QSPI.c](NOR_Config/W25Q512NWEIQ_EVKB_QSPI.c) |

## J-Link’e kaydetme

`JLinkDevices.xml` ve üç `.FLM` dosyasını aynı klasöre kopyalayın.

```text
%APPDATA%\SEGGER\JLinkDevices\RT1176_Ayri_FLM\
```

MCUXpresso’da J-Link GDB Server V8.44 kullanın. J-Link debug profilinin **Device** alanında tablodaki cihaz adını seçin. XML, cihazı ilgili FLM’ye bağlar. Flash loader seçimi J-Link tarafında yapılır. [SEGGER cihaz tanımı kılavuzu](https://kb.segger.com/J-Link_Device_Support_Kit#JLinkDevices_folder)

## Proje ve debug ayarları

1. Seçtiğiniz örnekteki `flexspi_nor_config_t` tanımını projenin mevcut NOR config dosyasına aktarın. Tam C dosyasını kullanacaksanız proje kaynakları içinde tek bir `.boot_hdr.conf` tanımı kalmasını sağlayın. Örnekler MCUXpresso RT1176 SDK başlıklarını kullanır.
2. Flash’tan XIP derlemesi için `XIP_EXTERNAL_FLASH=1` ve `XIP_BOOT_HEADER_ENABLE=1` tanımlı olmalı. Bu paket FlexSPI1 A1 bankı `0x30000000` için derlendi. FCB yükleme adresi `0x30000400`. Standart debug reseti için Cortex-M7 vektör tablosu `0x30002000` adresindedir.
3. Projeye ait J-Link debug konfigürasyonunda **Load Image**, **Use project binary** ve **Set breakpoint at main** seçeneklerini kullanın. Açıkça bir GDB başlangıç dosyası seçilmişse alanı temizleyin. Bu paketin Debug akışında ayrı PowerShell, GDB veya J-Link script dosyası kullanılmaz.
4. J-Link debug profilinin başlangıç komutları alanını aşağıdaki komutlarla doldurun. `SetCompareMode=0`, aynı imajla Debug başlatıldığında da yeniden programlamayı sağlar.

```gdb
monitor exec SetRestartOnClose=0
monitor reset
monitor exec SetCompareMode=0
monitor exec SetAllowFlashCache=0
```

Yükleme sonrası **Run Commands** alanını `monitor reset` olarak ayarlayın. Sonra Debug’ı başlatın. J-Link, yazılacak adresleri ve bölümleri projenin derlenmiş AXF/ELF dosyasından alır. [SEGGER J-Link komutları](https://kb.segger.com/J-Link_Command_Strings#SetCompareMode) · [RT1170 reset akışı](https://kb.segger.com/NXP_i.MX_RT1170#Reset)

## Mod ve revizyon kontrolleri

FLM, flash kimliğini SPI üzerinden kontrol eder. Macronix Octal seçeneklerinde JEDEC kimliği aynıdır, bu yüzden **NOR config ile aynı modun J-Link profilini seçin.** FLM gelen FCB alanı kendisine ulaştığında yapılandırmayı kontrol eder. J-Link sektörleri bu kontrolden önce silebilir.

Üç loader, gerçek `DIGPROG` değerini kullanır. `0x001170A0` için ROM API işaretçisi `0x0020001C`, `0x001170B0` ve `0x001170C0` için `0x0021001C` adresinden okunur. Custom kartta daha önce `0x001170C0` ölçüldü. EVKB donanım kılavuzu işlemciyi MIMXRT1176DVMAB olarak listeler. [NXP EVKB donanım kılavuzu](https://docs.nxp.com/bundle/MIMXRT1170EVKBHUG/page/topics/board_overview.html)

Üç sabit modlu FLM ve üç NOR config örneği derlendi. Sabit SDR ve DDR yükleyicileri, `DIGPROG=0x001170C0` okunan custom kartta J-Link V8.44 ile doğrulandı.

- Her iki mod, FCB ve imaj alanı boşken LED Blink’i yazdı ve doğruladı.
- SDR’den DDR’ye ve DDR’den SDR’ye geçişler doğrulandı.
- Her iki modda da aynı AXF yeniden silinip yazıldı.
- Her yüklemeden ve ayrı J-Link debug resetinden sonra uygulama `main`’de durdu.

EVKB Winbond QSPI profili derlendi. EVKB üzerinde donanım doğrulaması bekliyor.
