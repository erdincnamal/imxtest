# RT1176 birleşik J-Link FLM paketi

`JLinkDevices.xml` beş cihaz profilini `FLM/` klasöründeki yükleyicilere bağlar. Kullandığınız karta ve flash moduna göre J-Link Device ile NOR config’i birlikte seçin.

| Kart | Flash ve mod | J-Link Device | NOR config |
|---|---|---|---|
| Custom | MX25UW51245GXDQ00 Octal SDR | `MIMXRT1176B_MX25UW51245G_SDR_M7` | [MX25UW51245G_Octal_SDR.c](NOR_Config/MX25UW51245G_Octal_SDR.c) |
| Custom | MX25UW51245GXDQ00 Octal DDR | `MIMXRT1176B_MX25UW51245G_DDR_M7` | [MX25UW51245G_Octal_DDR.c](NOR_Config/MX25UW51245G_Octal_DDR.c) |
| EVKB | W25Q512NWEIQ QSPI | `MIMXRT1176_EVKB_W25Q512NWEIQ_QSPI_M7` | [W25Q512NWEIQ_EVKB_QSPI.c](NOR_Config/W25Q512NWEIQ_EVKB_QSPI.c) |
| EVKB | MX25UM51345GXDI00 Octal SDR | `MIMXRT1176_EVKB_MX25UM51345G_SDR_M7` | [MX25UM51345G_EVKB_Octal_SDR.c](NOR_Config/MX25UM51345G_EVKB_Octal_SDR.c) |
| EVKB | MX25UM51345GXDI00 Octal DDR | `MIMXRT1176_EVKB_MX25UM51345G_DDR_M7` | [MX25UM51345G_EVKB_Octal_DDR.c](NOR_Config/MX25UM51345G_EVKB_Octal_DDR.c) |

## J-Link kurulumu

Windows’ta `JLinkDevices.xml` ve `FLM/` klasörünü `%APPDATA%\SEGGER\JLinkDevices\RT1176_Birlesik_FLM\` altına aynı dizilimle kopyalayın. Önceki kayıtlarda aynı `ChipInfo Name` değerleri varsa eski paketlerin XML dosyalarını `JLinkDevices` ağacının dışına taşıyın. J-Link bu ağacı alt klasörleriyle birlikte tarar. [SEGGER JLinkDevices klasörü](https://kb.segger.com/J-Link_Device_Support_Kit#JLinkDevices_folder)

MCUXpresso’yu yeniden açın. **Run → Debug Configurations → CM7 J-Link Debug → J-Link Debugger** alanında tablodaki cihaz adını kullanın. Listede görünmüyorsa ve alan düzenlenebiliyorsa tam adı elle girin. `.launch` dosyasında aynı seçim `com.nxp.mcuxpresso.segger.device` anahtarının `value` alanına yazılır. IDE’nin J-Link GDB Server V8.44 yolunu kullandığını **Window → Preferences → MCUXpresso IDE → Debug Options → J-Link Options** altında kontrol edin. Proje kendi GDB Server yolunu seçiyorsa debug konfigürasyonundaki yolu da kontrol edin.

## Uygulama ve yeniden derleme

Uygulamada tablodaki NOR config’i kullanın. Bu paket FlexSPI1 A1 için hazırlanmıştır. XIP imajında FCB `0x30000400`, CM7 başlangıç vektörleri `0x30002000` adresindedir. A0, B0 ve C0 için ROM API seçimi `DIGPROG` üzerinden yapılır. Custom DDR profili uygulama verisindeki bayt çiftlerini değiştirir. EVKB Octal DDR profili bayt sırasını korur.

Keil µVision’da `RT1176_Birlesik_FLM.uvprojx` dosyası beş derleme hedefini açar. ARM Compiler 6.12 ile derlenen FLM, `FLM/` altına yazılır. Hazır FLM dosyaları önceki paketlerden kopyalandı. Custom Octal SDR ve DDR daha önce kartta test edildi. EVKB profilleri için donanım testi bekliyor.
