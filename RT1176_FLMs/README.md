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

## Keil µVision ile FLM derleme

Projeyi açmak için **Keil µVision 5**, **Arm Compiler 6.12** (`armclang`) ve **ARM.CMSIS 5.5.1** paketi kullanın. Projedeki cihaz tanımı `ARMCM7` ve linker dosyası `Source/loader.sct` olarak ayarlı.

1. [RT1176_Birlesik_FLM.uvprojx](RT1176_Birlesik_FLM.uvprojx) dosyasını µVision’da açın.
2. Araç çubuğundaki hedef listesinden kartınıza ve flash modunuza uygun hedefi seçin.
3. **Project → Build Target** menüsünü seçin veya **F7** tuşuna basın. Build Output penceresinde `0 Error(s), 0 Warning(s)` ve `1 file(s) copied` satırlarını kontrol edin. Beş FLM’yi yeniden üretmek için her hedefte bu adımı tekrarlayın.
4. Keil, bağlanmış `.axf` dosyasını `Objects/<hedef>/` altında oluşturur. Derleme sonu komutu bu dosyayı tablodaki adla `FLM/` klasörüne kopyalar. Aynı adlı mevcut FLM’nin üzerine yazılır. Kopyalama hatasında proje dizinindeki `FLM/` klasörünü ve yazma iznini kontrol edin.

| Keil hedefi | `FLM/` altındaki çıktı |
|---|---|
| `Octal SDR` | `RT1176B_MX25UW51245G_Octal_SDR.FLM` |
| `Octal DDR` | `RT1176B_MX25UW51245G_Octal_DDR.FLM` |
| `EVKB QSPI` | `RT1176_EVKB_W25Q512NWEIQ_QSPI.FLM` |
| `EVKB Octal SDR` | `RT1176_EVKB_MX25UM51345G_Octal_SDR.FLM` |
| `EVKB Octal DDR` | `RT1176_EVKB_MX25UM51345G_Octal_DDR.FLM` |

Paket klasöründe PowerShell açarak seçili bir hedefi komut satırından da derleyebilirsiniz. Keil farklı bir konuma kuruluysa `UV4.exe` yolunu güncelleyin.

```powershell
& 'C:\Keil_v5\UV4\UV4.exe' -b 'RT1176_Birlesik_FLM.uvprojx' -t 'EVKB Octal DDR' -o 'keil-build.log'
```

`-t` değerini tablodaki diğer hedef adlarıyla değiştirebilirsiniz. `keil-build.log` dosyasından derleme ve kopyalama sonucunu kontrol edin. J-Link’e daha önce kurduğunuz bir FLM’yi güncelleyecekseniz yeni çıktıyı kurulumdaki `FLM/` klasörüne aynı adla kopyalayın.

## Debugger FLM’yi nasıl çalıştırır?

FLM’nin ilk programlama çağrısı `SEGGER_FL_Prepare()` fonksiyonudur. Keil linker ayarında `--entry=SEGGER_FL_Prepare` tanımlıdır. J-Link DLL, FLM’nin ELF simgelerinden `SEGGER_FL_*` fonksiyonlarının adreslerini bulur ve sıradaki işleme göre her birini ayrı çağırır. Uygulamanın `main()` fonksiyonu daha sonra, uygulamanın kendi başlangıç kodundan çalışır. [SEGGER Flash Loader](https://kb.segger.com/SEGGER_Flash_Loader)

Bir çağrıda J-Link, SWD üzerinden program sayacını (PC) RAM’deki fonksiyonun girişine, stack pointer’ı (SP) geçici yığına ayarlar. Örneğin `Program` çağrısında hedef adresi, uzunluğu ve RAM tamponunun adresini Arm çağrı kuralına göre çekirdeğe verir. Cortex-M7 fonksiyonu yürütür. J-Link işlem sonucunu alıp sıradaki çağrıya karar verir. [SEGGER Flash Loader çağrı arayüzü](https://kb.segger.com/SEGGER_Flash_Loader#SEGGER_FL_Program)

1. **FLM’yi seç ve RAM’e yükle.** MCUXpresso, uygulama AXF’sinin yükleme adreslerini ve verisini GDB Server’a gönderir. J-Link, seçtiğiniz `Device` ve `0x30000000` flash bankı için `JLinkDevices.xml` içindeki FLM’yi bulur. Çekirdeği durdurur ve FLM’nin kodunu Cortex-M7’nin iç RAM’indeki `WorkRAMAddr` alanına yükler. Bu pakette alan `0x20281000` adresinde başlar. [Cihaz eşleştirmesi](JLinkDevices.xml)
2. **`SEGGER_FL_Prepare()` ile flash’ı hazırla.** FLM, `DIGPROG` üzerinden RT1176 revizyonunu okuyup A0 veya B0/C0 ROM API tablosunu seçer. `FlexSPI1` üzerinden SPI erişimini kurar ve flash’ın JEDEC kimliğini kontrol eder. Octal parça önceki oturumdan Octal modda kalmışsa gerektiğinde SDR ve DDR reset dizilerini dener. [Custom ve QSPI kaynağı](Source/mx25uw51245g-sfl.c) · [EVKB Octal kaynağı](Source/mx25um51345g-sfl.c)
3. **Sil ve yaz.** J-Link, AXF’deki adreslere göre hangi sektörlerin işleneceğini belirler. Karşılaştırma açıksa eşleşen sektörleri atlayabilir. `SetCompareMode=0` ile bu ön karşılaştırma atlanır. J-Link, `SEGGER_FL_Erase()` ile gerekli 4 KiB sektörleri sildirir. Sonra veriyi hedef RAM’deki tampona koyar ve `SEGGER_FL_Program(adres, boyut, tampon)` çağrısını yapar. Cortex-M7 bu fonksiyonu RAM’den çalıştırır, flash’ı 256 baytlık sayfalarla yazar ve her sayfayı geri okuyup karşılaştırır. AXF bir FCB içeriyorsa FLM, FCB’yi `0x30000400` adresine yazar. Custom Octal DDR profilinde bayt çifti değişimi FCB dışındaki alana uygulanır. [SEGGER programlama sırası](https://kb.segger.com/J-Link_flash_programming#SEGGER_Flashloader)
4. **Yükleme sonrası doğrula ve flash’ı XIP’e hazırla.** `SetVerifyDownload=3` seçiliyse J-Link, programlanan sektörler için geri okuma yöntemiyle L2 doğrulaması yapar. `SEGGER_FL_Restore()` sonrasında uygulamanın FCB’sindeki okuma ayarları FlexSPI’ye uygulanmış olur. Octal profiller flash’ı FCB’deki SDR veya DDR moduna geçirir. J-Link de geçici programlama sırasında kullandığı hedef RAM’i ve çekirdek kayıtlarını geri yükler. [SEGGER doğrulama seçenekleri](https://kb.segger.com/J-Link_Command_Strings#SetVerifyDownload)
5. **Uygulamayı başlat.** Yükleme sonrası reset ayarına göre debugger, uygulamanın başlangıç vektörlerini kullanır. Bu paketin CM7 düzeninde ilk stack pointer `0x30002000`, reset handler adresi `0x30002004` konumundan okunur. Uygulamanın startup kodu yürür ve `main()` breakpoint’i ayarlıysa debugger orada durur. [SEGGER RT1170 reset akışı](https://kb.segger.com/NXP_i.MX_RT1170#Reset)

J-Link logunda `Downloading RAMCode`, `Executing SEGGER_FL_Prepare`, `Start of flash programming`, `Start of verifying flash` ve `Executing SEGGER_FL_Restore` satırları bu sırayı gösterir. En sonda görülen uygulama breakpoint’i, FLM çağrılarının tamamlanıp uygulama debug oturumunun başladığı noktadır.

## Uygulama ayarları

Uygulamada tablodaki NOR config’i kullanın. Bu paket FlexSPI1 A1 için hazırlanmıştır. XIP imajında FCB `0x30000400`, CM7 başlangıç vektörleri `0x30002000` adresindedir. A0, B0 ve C0 için ROM API seçimi `DIGPROG` üzerinden yapılır. Custom DDR profili uygulama verisindeki bayt çiftlerini değiştirir. EVKB Octal DDR profili bayt sırasını korur.

Hazır FLM dosyaları önceki paketlerden kopyalandı. Custom Octal SDR ve DDR daha önce kartta test edildi. EVKB profilleri için donanım testi bekliyor.
