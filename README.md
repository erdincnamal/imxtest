# RT1176B / MX25UW51245G otomatik entegrasyon

Bu paket Windows’ta MCUXpresso IDE’nin yönetilen MIMXRT1176 Cortex-M7 projesine kurulur. Hedef, MX25UW51245G’nin FlexSPI1 A1’e bağlı olduğu custom karttır. J-Link’in ve kullanılan IDE workspace’inde RT1176 SDK’sının kurulu olması gerekir. Doğrulamada MCUXpresso IDE 25.6.136 ve J-Link 8.44 kullanıldı.

1. ZIP’i yeni projenin fiziksel köküne aç. `.project` ve `.cproject` ile aynı dizinde `RT1176B-Integration` klasörü oluşur.
2. Proje kökünden PowerShell’de kurulum komutunu çalıştır.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\RT1176B-Integration\Install-RT1176B.ps1
```

3. MCUXpresso’da projeyi yenile veya yeniden aç. **Debug Configurations** altında proje adına göre oluşturulan **<Proje Adı> RT1176B J-Link** profilini seç. Profil açıldığında seçili yapılandırmayı derler.

Kurulum proje adını `.project` dosyasından, build dizinini, çıktı adını ve uzantısını `.cproject` dosyasından okur. `.axf` ve `.elf` desteklenir. `Debug` varsa onu, ardından tek bir debug yapılandırması varsa onu seçer. Birden çok aday varsa `-Configuration` ile yapılandırma adını ver. Projeyi yeniden adlandırırsan veya artifact ayarlarını değiştirirsen profilin yeni değerlerle oluşturulması için scripti tekrar çalıştır.

Dosya adında boşluk kullanılabilir. MCUXpresso 25.6.136 ile gelen Windows GDB’de Türkçe karakterli ELF yolu sembol yüklemede hata verdi. Bu sürümle debug için projenin fiziksel yolunda ve çıktı adında ASCII karakterleri kullan.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\RT1176B-Integration\Install-RT1176B.ps1 -Configuration "FlexSPI_Debug"
```

| Seçenek | Kullanım |
| --- | --- |
| `-ProjectPath` | Kurulum klasörünü proje dışına açtıysan `.project` dosyasını içeren dizini ver. |
| `-Artifact` | Projeye göre özel AXF/ELF yolunu belirt. Varsayılan yol yapılandırmanın build dizini ve artifact adından hesaplanır. |
| `-KeepFcb` | Projedeki FCB kaynağını kullan. Kurulum uyumlu Macronix FCB’yi otomatik tanıdığında onu korur. |
| `-StopAt` | İlk donanım breakpoint’i için bir sembol adı ver. Varsayılan `main`. |
| `-Objcopy` | GNU objcopy standart MCUXpresso dizininde veya PATH’te bulunmuyorsa EXE yolunu ver. |

Kurulum `XIP_EXTERNAL_FLASH=1` ve `XIP_BOOT_HEADER_ENABLE=1` tanımlarını ayarlar. SDK’nın yönetilen linker belleğinde FlexSPI1 flash bölgesini 64 MiB olarak ayarlar. FCB ve IVT kaynaklarını derlenen C/C++ dosyalarındaki boot bölümlerinden bulur. Gerektiğinde FCB’nin başlangıç verisini değiştirir veya eksik boot kaynağını ekler. Özel linker kullanıyorsan FCB `0x30000400`, IVT `0x30001000` ve CM7 vektör tablosu `0x30002000` yerleşimini projenin linker scripti sağlamalı. [NXP SDK XIP boot başlıkları](https://mcuxpresso.nxp.com/mcuxsdk/24.12.00/html/boards/evkbmimxrt1170/gettingStarted/topics/how_to_add_or_remove_boot_header_for_xip_targets.html)

Script `JLinkDevices.xml` ve FLM’yi geçerli Windows kullanıcısının SEGGER cihaz dizinine kaydeder. Üzerine yazdığı dosyaların ilk sürümlerini ilgili kökteki `.rt1176b-backup` altında saklar. Bir başka proje, aynı paketle kendi launch dosyasını alır. [SEGGER cihaz veritabanı](https://kb.segger.com/J-Link_Device_Support_Kit)

Debug profili her yeni oturumda AXF/ELF içindeki en çok 256 KiB’lık tam XIP imajını FCB ve IVT dahil yeniden yazar. İmaj aynı kalsa da yazım gerçekleşir. Yordam imajın kapsadığı sektörleri ve son sektörde koruduğu baytları doğrular. Yazım doğrulandıktan sonra IDE seçilen sembolde durur. Restart mevcut oturumun uygulamasını resetler.
