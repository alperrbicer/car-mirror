# Mirivo · 2 Ekim 2026

Devam noktası ve bütün açık işler: [NEXT_STEPS.md](NEXT_STEPS.md).

4 Ekim 2026 disk temizliği: geçmiş derleme klasörleri, `.xcresult` paketleri ve
geçici test görselleri silindi. Aşağıdaki bu dosyalara atıflar geçmiş koşuların
kaydıdır; ayrıntılı paketler artık yerelde bulunmaz. Küçük log/JSON kayıtları,
TestFlight arşivi/IPA ve build sayacı korundu. Derleme araçları artık ortak
önbellek kullanır; bakım komutu için [DEPLOYMENT.md](DEPLOYMENT.md) belgesine bak.

## 3 Ekim 2026 — TV bağlantısı

- Ana ekran, oynatıcı ve tam ekrana TV seçimi eklendi. Google Cast alıcısı etkin Android/Google TV ve Cast cihazları için resmi Google Cast iOS SDK 4.8.6 kullanılır. AirPlay için sistem aygıt seçicisi ve Ekran Yansıtma yönergesi bulunur. Android TV sürümü tek başına alıcının varlığını doğrulamaz; kullanıcının Nextstar Android TV 14 cihazı henüz fiziksel olarak sınanmadı. Yalnız Miracast/DLNA destekleyen cihazlar bu uygulamayla keşfedilmez.
- SDK, checksum doğrulanan resmi statik XCFramework ve sabit GTMSessionFetcher 3.5.0 bağımlılığıyla SwiftPM üzerinden eklenir. Lisans bildirimleri Ayarlar'da, SDK kaynakları ve gizlilik manifestleri uygulama paketindedir. Cast tanılama analitiği kapalı; keşif TV seçimi açıldığında başlar. SDK kendi yapılandırmasını Google'dan indirebilir.
- İnternet yayınını TV doğrudan sağlayıcıdan alır. Oynat/duraklat, süre, sarma ve hata durumu alıcıdan izlenir; TV'den telefona dönüşte mevcut konum ve duraklatma tercihi korunur. Başlatma hatası aktif oynatma/Şimdi oynatılıyor bilgisi bırakmaz. Başka bir gönderenin başlattığı içerik otomatik durdurulmaz.
- HLS/MP4 ve diğer içeriklerin açılması TV'nin codec desteği ve sağlayıcının erişim/CORS koşullarına bağlıdır. MKV için otomatik dönüştürme uygulanmaz; iPhone'da VLCKit ve uygun AirPlay ekranda sistem Ekran Yansıtma yolu korunur. Korumalı içeriğin engelleri aşılmaz.
- ReplayKit HLS yayını ve seçilmiş yerel medya için oturuma özel yerel HTTP adresleri kullanılır. Cast web alıcısının GET/HEAD/OPTIONS ve byte-range isteklerine CORS yanıtları eklendi; yanlış oturum adresi dosya/veri döndürmez. Yerel dosya aktarımında Mirivo'nun açık kalması gerekir.
- VLCKit Chromecast yolu kullanılmıyor: ulaşılamayan alıcı denemesinde libVLC'nin yakalanmayan C++ hatası uygulamayı kapattı. Bağlantı resmi Google SDK'sına taşındı. Bonjour ilanı tek başına resmi SDK'da geçerli alıcı oluşturmadığından simülatör testleri keşif/gerçek TV kabulü olarak sunulmaz.
- Son doğrulama: **5 TV durumu/konum/harici yüzey testi + 1 gerçek yerel HTTP sunucusu testi + 9 HLS/HTTP çekirdek testi + 20 mevcut oynatıcı testi = 35 geçti, 0 hata**. Üç opt-in sağlayıcı testi bu koşuya alınmadı. Kanıtlar: `build/tv-connection-tests.log`, `build/tv-http-tests.log`, `build/tv-playback-regression.log`. 22 dil/247 anahtar statik denetimi, paket içindeki SDK kaynakları/gizlilik manifestleri/lisans ve proje kurulumunun tekrarda çoğalmaması da doğrulandı.
- Fiziksel Nextstar keşfi, canlı yayın/film görüntüsü ve sesi, AirPlay, arka plandan geri dönüş, aynı TV'de başka gönderenle devir ve uzun izleme henüz doğrulanmadı. Bu kaynak değişiklikleri önceki TestFlight build 7'ye dahil değildir; bu çalışmada yükleme yapılmadı.

Kaynak sürüm **1.0 (6)**; TestFlight dağıtım adayı **1.0 (7)**. Mirivo + A grafit/mint kimliği ve otomobilli iki ekran logosu korunuyor. TestFlight beta inceleme gönderimi tamamlandı; Apple durumu **Waiting for Review**. EV6'da görüntü ve ses, fiziksel CarPlay kabulü ve App Store yayın incelemesi henüz doğrulanmadı.

## 3 Ekim 2026 — TestFlight dağıtım adayı

- Kullanıcının TestFlight hazırlığı ve beta inceleme gönderimi talebiyle **1.0 (7), CarPlay Audio** arşivi oluşturuldu. Kaynak build değeri 6 olarak korunur; arşiv ana uygulama ve uzantı için 7 kullanır. Pro satışları kapalıdır.
- `bun run release:check` başarılı: 22 dil, 207 anahtar, 4.554 çeviri değeri ve 12 HTML sayfası. `bun run check` başarılı: 17 script testi, 39 Swift testi ve imzasız simülatör derlemesi.
- İmzalı Release arşivi ve App Store dağıtım IPA'sı başarılı. Ana uygulama ve uzantının dağıtım profilleri, bundle/sürüm/build, App Group ve CarPlay Audio yetkisi script tarafından doğrulandı.
- API anahtarı yapılandırılmamış olduğundan yükleme mevcut Xcode Apple hesabıyla yapıldı. `xcodebuild -exportArchive` **Upload succeeded / EXPORT SUCCEEDED** döndürdü; Apple paketi işlemeye başladı. Bu sonuç beta incelemesine gönderim veya Apple onayı değildir.
- App Store Connect TestFlight → iOS → Build Uploads ekranında **Version 1.0, Build (7), Processing** ve 3 Ekim 2026 16:29 yükleme zamanı canlı olarak görüldü.
- Kanıtlar: `build/testflight-check.log`, `build/testflight-archive.log`, `build/testflight-export.log`, `build/testflight-upload.log`, `build/deploy/testflight-upload.json`. Arşiv/IPA tam yolları JSON kaydındadır.
- Türkçe/İngilizce beta açıklaması ve test hedefleri `Release/AppStore/testflight-localizations.json`; ayrı beta inceleme adımları `Release/AppStore/testflight-review-notes.txt` içindedir. Mağaza inceleme hazırlığı dosyası ayrı korunur.
- Kullanıcının açık paylaşım onayı ve verdiği iletişim telefonu ile inceleme iletişim bilgileri Apple'a kaydedildi. Türkçe/İngilizce beta açıklamaları, belge bağlantıları, test hedefleri ve İngilizce inceleme notları kaydedildi. Giriş gerekmiyor.
- Apple'ın dış beta inceleme akışı için `Mirivo Internal` (otomatik dağıtım kapalı) ve `Mirivo Beta` grupları oluşturuldu. Build 7, dış `Mirivo Beta` grubuna eklendi ve **Submit for Review** tamamlandı. Grup ekranında **Build 1.0 (7) — Waiting for Review** canlı doğrulandı. Gruplarda test kullanıcısı yok; otomatik bildirim kapalı, public link açılmadı. TestFlight onayı henüz alınmadı; App Store yayınına gönderim yapılmadı.
- Ek `MirivoTests/CarPlayAudioTests` simülatör koşusu test sonucu üretmeden tanılama toplamasında takıldı ve durduruldu (`TEST INTERRUPTED`, çıkış 75). Bu koşu başarılı test sayılmaz. Kanıt: `build/testflight-playback-tests.log`. İlk denemede yanlış test hedef adı kullanılmış, ardından doğru `MirivoTests` hedefiyle tekrar denenmiştir.
- Arşiv `CreationDate` alanı `plutil` JSON dönüşümünü engellediğinden dağıtım scripti yalnız `ApplicationProperties` alanını çıkaracak şekilde düzeltildi; 17 script testi tekrar geçti ve aynı arşivin export'u başarılı oldu.
- Fiziksel iPhone/araç ve CarPlay Video doğrulaması bu işlemde yapılmadı.

## Audio onayı sonrası

Kullanıcının paylaştığı Apple e-postası CarPlay Audio App (CarPlay framework) yetkisinin hesaba tanımlandığını doğruluyor. Xcode otomatik imzalama ile **Audio yetkili Release cihaz derlemesi başarılı oldu**. Ana uygulamanın gerçek kod imzasında ve gömülü Apple profilinde Audio var, Video yok; uzantıda yalnız App Group var. Her iki imza ve ortak grup eşleşmesi doğrulandı. Profil yenilemesi Chrome kullanılmadan Xcode üzerinden yapıldı. Bu, geliştirme sertifikasıyla imzalı bir derlemedir; fiziksel kurulum veya App Store dağıtım imzası değildir.

Varsayılan `CarMirror` yapılandırması Audio kullanır. `CarMirror CarPlay` veya `--carplay-video` açıkça seçildiğinde Audio + Video gerekir. Bir yapılandırmanın başarısız olması diğerine otomatik geçiş yapmaz. Audio sürümünün CarPlay menüsünde kaynaklar, Şu An Çalıyor ve durdurma bulunur; video eylemleri bulunmaz. Ses oynatma `.longFormAudio` oturumu kullanır, harici video çıkışını kapatır ve sistemin oynat/duraklat/durdur komutlarına bağlanır. Video desteği olan araçta bile Audio imzası video yolunu açmaz.

Kanıtlar: `build/carplay-audio-device.log`, `build/carplay-audio-signing.json`; **34 Swift testi** (29 çekirdek + 5 medya), **17 kurulum testi** ve **2 uygulama içi ses testi** geçti. Sonuçlar `build/carplay-audio-core.log`, `build/carplay-audio-scripts.log`, `build/carplay-audio-tests.log` ve `build/carplay-audio-tests.xcresult` içinde. Video onayı, fiziksel CarPlay ses/görüntü kabulü ve dağıtım kontrolü açık.

## Uygulanan ürün kapsamı

- Yansıt, Kaynaklar ve Ayarlar sekmeleri; kısa açılış geçişi, koyu tema, büyük yazı ve Hareketi Azalt desteği. Standart, koyu ve renklendirilmiş ikonlar aynı logo geometrisini kullanır.
- M3U, doğrudan yayın ve Xtream Codes kaynakları; kanal/grup arama, kaynak silme, yerel oynatıcı, kaynak altyazıları ve büyük kontrollü araç modu. Kaynak adresleri ve hesap bilgileri Keychain'de, kaynak adları cihazda saklanır. İçerik veya IPTV hesabı sağlanmaz.
- ReplayKit ekranı ve uygulama sesi, aynı zaman tabanında H.264/AAC yayınına dönüştürülür. Dengeli 960×540/20 fps ve yüksek 1280×720/30 fps seçenekleri vardır. Ses, görüntüyle taşınabilir veya kaynak uygulamanın ses yolu korunabilir. Araçtaki senkron ve çift ses davranışı ayrıca ölçülecek.
- iOS 26 ve desteklenen cihaz/dilde SpeechAnalyzer ile cihaz içi canlı altyazı. Dil modeli ayarlardan hazırlanır; geçici altyazı videoya eklenir. Ses ve döküm dosyaya veya geliştirici sunucusuna gönderilmez. Gerçek yayın uzantısının bellek ve konuşma kabul testi açık.
- CarPlay Audio listesinde kaynak kitaplığı ve sistem oynatma kontrolleri bulunur. Video yapılandırması ayrıca ekran paylaşımını içerir; video eylemleri yetki ve sistemin video desteği bildirimine bağlıdır. Uzun kanal listeleri aynı sayfa üzerinde ilerler; CarPlay gezinme yığını büyümez. Gerçek harici ekran sahnesi sağlanırsa ortak oynatıcı kullanılır.
- Oturum kimliği, eski bildirimler, duraklama, kesinti, yeniden deneme, zaman aşımı, durdurma ve temizleme işlenir. Ekran yakalamanın başlaması tek başına araçta görüntü var sayılmaz.
- Son 10 oturum / toplam 5 MiB sınırında teknik kayıt, rapor paylaşımı ve kayıt silme. URL, parola, erişim anahtarı, ekran, ses, altyazı ve cihaz adı rapora yazılmaz; rapor otomatik gönderilmez.
- Haftalık, yıllık ve tek ödemelik Pro için StoreKit 2 ürün yükleme, doğrulanmış erişim, satın alma, geri yükleme, işlem güncellemeleri, iade ve sona erme akışları hazırlandı. **Satış kapalıdır; mevcut özellikler ücretsizdir ve hiçbir sürümde reklam yoktur.** Gerçek fiyatlar daha sonra App Store Connect'ten gelecek.
- 22 dilde uygulama ve yayın uzantısı metinleri; aranabilir dil seçimi, sistem/bölge eşleştirmesi; kalite, ses ve altyazı ayarları. Çevrimdışı gizlilik/EULA/yardım sayfaları Türkçe/İngilizce seçilebilir. Destek: `alperrbicer@gmail.com`. Arapça, İbranice, Tayca, Vietnamca, Endonezce ve Hintçe 3 Ekim talimatıyla eklendi; güncel kapsam ve doğrulama `docs/LOCALIZATION.md` içinde kayıtlıdır.

## Teslim dosyaları

- `Release/mirivo-netlify.zip`: Türkçe/İngilizce 12 HTML sayfası, stil, logo ve Netlify başlık/yönlendirme dosyaları. ZIP kökünde `index.html` bulunur. 3 Ekim 2026’da Chrome üzerinden Netlify’a yüklendi ve https://mirivo-support.netlify.app adresinde herkese açık yayımlandı.
- `Release/README.txt`: yükleme ve mağazaya girilecek URL yolları.
- `Release/AppStore/{tr,en}/metadata.json`: mağaza metinleri; `review-notes.txt` ve `privacy-inventory.json`: inceleme/veri hazırlığı. Portalda yüklenmiş oldukları iddia edilmiyor.
- `Resources/Legal`: uygulamada internet olmadan açılan aynı belgeler. Belge ekranındaki Safari düğmesi seçili sayfanın Türkçe/İngilizce web sürümünü açar. Destek formu kullanılmaz.
- Netlify tanıtım rozeti kapatıldı. Yayındaki 12 HTML sayfası HTTP üzerinden doğrulandı; belge metinleri yerel dosyalarla aynı ve sayfalarda script yok. Kanıt: `build/netlify-url-checks.json`.
- App Store Connect: Türkçe ve İngilizce (ABD) gizlilik politikası, destek ve pazarlama URL’leri kaydedildi. İngilizce yerelleştirme eklendi. Apple Standart EULA korunuyor; ürün koşulları `/tr/terms.html` ve `/en/terms.html` adreslerinde. Binary/inceleme gönderimi yapılmadı.
- `docs/PRO_RELEASE.md`: satışın daha sonra açılması için ürün kimlikleri ve kontroller.
- `docs/RELEASE_ACCEPTANCE.md`: fiziksel cihaz, araç ve dağıtım kabul listesi.

## Yerel doğrulama

| Kontrol | Sonuç / kanıt |
| --- | --- |
| Swift çekirdek ve medya | **34 geçti**: 29 çekirdek (3 Audio/Video ayrımı ve 3 dil davranışı testi dahil), 5 medya. Gerçek H.264/AAC üretimi ve çözümü, kaynak sesin varlığı, zaman çizgisi, HTTP erişimi, tampon sınırları, 10 kez durdurma, kaynak ayrıştırma ve kayıt mahremiyeti. `build/carplay-audio-core.log` |
| Kurulum araçları | **17 geçti**. Audio/Video/önizleme ayrımı, kimlik/profil, cihaz seçimi ve başarısız derleme sonrası kurulumu durdurma dahil. `build/carplay-audio-scripts.log` |
| CarPlay Audio oynatıcı | **2 geçti**: gerçek ses dosyasını oynatma, ses türü/başlık bilgisi, `.longFormAudio` rotası, oynat/duraklat, komut temizliği ve Video'dan Audio'ya geçişte harici videonun kapatılması. iOS 26.5 simülatörü; araç hoparlörü veya direksiyon kontrolleri kanıtı değildir. `build/carplay-audio-tests.xcresult` |
| Site ve yerelleştirme | **Geçti**: 12 HTML, 16 dil × 183 anahtar (2.928 çeviri), çevrimdışı kopyalar, bağlantılar, plist'ler, satışın kapalı olması ve ZIP içerik eşleşmesi. Audio yardım adımları da Netlify ZIP'ine eklendi. `build/release-static-checks.json` |
| Debug uygulama derlemesi | **Başarılı**: güncel Audio oynatıcı testleri için simülatör uygulaması derlendi ve iki hedefli test geçti. `build/carplay-audio-tests.log`. Önceki arayüz testlerinin kapsamı aşağıda ayrıca kayıtlıdır. |
| Release cihaz derlemesi | **Audio yetkisiyle imzalı derleme başarılı**: `build/carplay-audio-device.log`. Uygulama/uzantı 1.0 (6), gerçek imza ve gömülü Apple profilleri doğrulandı: `build/carplay-audio-signing.json`. Son pakette 16 dil, güncel belgeler, kapalı Pro satışları ve test StoreKit dosyasının bulunmaması da doğrulandı: `build/carplay-audio-validation.json`. Fiziksel kurulum ve App Store dağıtım sonucu değildir. |
| Uygulama/arayüz testleri | `build/localization-ui.log` içinde 16 dilde açılış, İngilizce büyük yazı/yatay kullanım ve Türkçe ürün/çevrimdışı belge akışları geçti; bu koşunun tamamı başarılı olmadı. Görünür arama alanı düzeltildikten sonra dil arama, anında değiştirme, yeniden açılışta koruma ve sistem diline dönüş testi **geçti**: `build/localization-selection-ui.xcresult`. Japonca ayarlar/belge ve arama ekranları ayrıca incelendi. Bu sonuçlar, aşağıdaki son belge gezinme değişikliğinden önceye aittir. Önceki en büyük yazı/yatay paylaşım kontrolü `build/production-unlocked-qa.xcresult` içinde; Keychain kaydet/oku/sil testi de daha önce geçti. |
| Son belge gezinme kontrolü | **Açık**: HTML içindeki dil/sayfa bağlantılarının yerel başlık ve dil seçimiyle eşleşmesi düzeltildi ve son Release derlemesine dahil edildi. Sonraki arayüz denemelerinde dokunmalar belge ekranına ulaşmadan sonuç vermedi; bilgisayar kontrol aracı da zaman aşımına uğradı. Neden kesinleştirilemedi. Bu değişikliğin ekrandaki davranışı doğrulanmış sayılmıyor. Kayıtlar: `build/localization-legal-final.log`, `build/localization-clean-ui.log`. |
| StoreKit | **Doğrulanamadı**: iOS 26.5 test ortamı `SKInternalErrorDomain Code=3` / `notEntitled` verdi. İki iOS 27 denemesinde test oturumu başlamadı; bellek baskısı nedeniyle denemeler durduruldu. `build/production-qa27-resumed.log`, `build/production-storekit-final.log`. Satın alma, geri yükleme, iade ve abonelik bitişi geçmiş sayılmıyor; satış açılmadan önce bu testler ve gerçek sandbox senaryoları tamamlanacak. |

Ses/video testinde iki iz 0'dan başladı; ses 3,967 sn, video 4,010 sn sürdü. Bu yerel kodlama kanıtıdır; araç gecikmesini veya EV6 ses rotasını ölçmez.

## Apple ve fiziksel cihaz durumu

Son tarayıcı portal kontrolü 2 Ekim 2026'daki önceki Chrome çalışmasına aittir. Audio için yeni kanıtlar kullanıcının Apple e-postası ve bu çalışmadaki Xcode imzalama/profil çıktılarıdır; Chrome açılmadı.

- Takım `3T2VY64864`; ana uygulama `com.alperbicer.carmirror`; uzantı `.broadcast`; App Group `group.com.alperbicer.carmirror`.
- CarPlay Audio onaylandı; ana uygulamada Audio içeren geliştirme profili ve kod imzası doğrulandı. Ana profilin son geçerlilik tarihi `2027-10-02T17:48:24Z`. Video için önceki talep alındı bilgisi mevcut; onay veya Video profili doğrulanmadı.
- [Mirivo App Store Connect kaydı](https://appstoreconnect.apple.com/apps/6818560405/distribution/info): `6818560405`, SKU `mirivo-ios`, Türkçe ana dil, iOS 1.0 taslağı. Binary veya inceleme gönderimi yapılmadı.
- Telefona en son kurulduğu doğrulanan sürüm **0.1.0 (4) iPhone önizlemesi**; CarPlay yetkileri yok. Build 6 bu çalışma sırasında fiziksel telefona kurulmadı.
- CarTV 1.1.1 (35) kurulum bildiriminde Audio/Video yetkileri ve harici ekran rolleri görüldü. Bu bilgi CarTV'nin iç aktarım tekniğinin çözüldüğü anlamına gelmez.

Audio imzalı sürümle iPhone 16 Pro + 2024 Kia EV6'da simge/sahne, kaynak sesi ve oynatma kontrolleri henüz sınanmadı. Kablo ve markasız adaptör ayrı sınanacak. Video yetkisi ve gerçek imzadan sonra YouTube ve Smarters Player ile görüntü/ses, 30 dakikalık kullanım, 10 başlat/durdur, kesinti, yön değişimi ve altyazı belleği ölçülecek. Bunlar tamamlanmadan ürünün production kabulü kapatılmaz.


### 2026-10-03 — Kaynak ve oynatma sürekliliği

- Kanal listeleri oturum belleğinde kaynak kimliğine göre tutulur; eşzamanlı yüklemeler birleştirilir. Düzenle/sil/temizle ve elle yenile önbelleği geçersiz kılar. Medya adresleri diske önbelleklenmez.
- Kategori/kanal listelerinde ve ana ekranda aktif oynatıcı çubuğu aynı oynatma oturumunu açar.
- HLS/MP4 için AVPlayer korunur. MKV/WebM/AVI/TS için resmi VideoLAN VLCKit 4 geliştirme paketi, `2e0868f5ed40fe59cd92f377645fdcc260c6e759` revizyonuna sabitlenmiştir. SwiftPM dosyası binary checksum doğrulaması içerir; uygulama LGPL lisans metnini ve kaynak bağlantılarını gösterir. Yayın öncesi bağımlılığın geliştirme sürümü olduğu dikkate alınmalıdır.
- AVPlayer arka plan politikası `continuesIfPossible`; mevcut audio background mode ve playback audio session korunur. Otomatik inline PiP açıldı ve native PiP arayüz geri dönüş delegate'i eklendi. MKV video yüzeyi VLCKit'in örnek tamponlu PiP protokolünü kullanır.
- Opt-in sağlayıcı testleri simülatör uygulamasının `tmp/mirivo-vod-probe.json` (`original`) ve `tmp/mirivo-live-playback-fixture.json` (`ts`, `m3u8`) dosyalarını okur. Dosyalar hesap bilgisi içerebilir; depoya konulmaz ve testten sonra silinir.
- Gerçek sağlayıcıda örnek MKV bölümünün görüntü boyutu ve oynatma zamanı ilerlemesi ile HLS canlı yayını simülatörde doğrulandı. Fiziksel iPhone PiP, kilit ekranı ve arka plan/ön plan geçişi bu kayıtla doğrulanmış sayılmaz.

### 2026-10-03 — Film/dizide ilk açılışta siyah görüntü

- VLC'nin ortak video yüzeyi, liste önizlemesinin güncellemeleriyle ana oynatıcıdan geri alınabiliyordu. Görünür ve boyutu hazır alanlar arasında tam ekran → ana oynatıcı → önizleme önceliği eklendi; kapanan alanın temizliği yeni görüntü sahibini bozmuyor.
- VLC'nin iç çizim görünümü de ana alana göre yeniden boyutlandırılıyor. Önizlemenin 88×50 boyutunda veya sıfır boyutta kalması giderildi; oynatma oturumu yeniden başlatılmıyor.
- Uygulamanın bağlantı test videosundan üretilen yerel MKV ile hata önce tekrarlandı, ardından ilk açılışta tam ekrana geçmeden görüntü alındı. İlk açılış, önizleme güncellemesi, tam ekrandan dönüş ve mevcut oynatma testlerinde **15 geçti, 2 opt-in sağlayıcı testi atlandı, 0 hata**. Kanıt: `build/inline-playback-tests.log`, `build/inline-playback-first-open.png`. Fiziksel iPhone kontrolü henüz yapılmadı.

### 2026-10-03 — Tam ekranda döndürme

- Başlık ve oynatma kontrolleri videodan yükseklik alan satırlardan, video üzerine çizilen kontrollere taşındı. Tam ekran ve araç modunda video tüm pencereyi kullanır; görüntü oranı korunur. MKV'nin ikinci duraklat/PiP satırı tam ekranda kaldırıldı, PiP düğmesi başlığa taşındı.
- Yatayda eylemler ve oynatma düğmeleri tek satıra sığar. Kontroller dokunarak açılıp kapanır ve oynatma sırasında 4 saniye sonra gizlenir. Duraklatma, zaman çizgisini sürükleme, kanal seçimi, kontrol kilidi ve VoiceOver otomatik gizlemeyi engeller.
- MKV ve MP4 ile iki modda dikey → yatay sol → yatay sağ → dikey döngüsü, video ve renderer boyutlarının pencereyle eşleşmesi ve oynatma oturumunun korunması doğrulandı. Oynatma grubunda **17 geçti, 2 sağlayıcı testi atlandı** (`build/fullscreen-rotation-tests.log`); kontrollerin gizlenmesini içeren iki genişletilmiş dönüş testi ayrıca geçti (`build/fullscreen-visibility-tests.log`). Kontroller açık/gizli yatay görüntüler `build/rotation-screenshots/` altında incelendi. Fiziksel iPhone doğrulaması yapılmadı.

## 3 Ekim — ertelenen altı dil

Arapça, İbranice, Tayca, Vietnamca, Endonezce ve Hintçe eklendi; uygulama ve yayın uzantısı 22 dil içeriyor. Güncel katalog dil başına 207 anahtar. Statik denetim, dört dil çekirdek testi, altı dil açılışı, RTL dil tercihi kalıcılığı, Arapça/İbranice kaynak girişi ve İngilizce hukuki belgeye geçiş testleri geçti. Bunlar ayrı test koşularının sonuçlarıdır; ayrıntılı kayıt ve paket yolları `docs/LOCALIZATION.md` içinde. Fiziksel cihaz/araç doğrulaması yapılmadı. Yukarıdaki 2 Ekim sonuçları kendi tarihsel kapsamını korur.

### 2026-10-03 — Film/dizide ileri sarınca görüntünün beklemesi

- Gerçek sağlayıcıdaki örnek MKV'de sorun tekrarlandı. HTTP Range istekleri doğru `206` yanıtı verdi ve dosyanın Cues indeksi bulundu; buna rağmen varsayılan MKV sarma yolu 120. saniyeye giderken yaklaşık 3.000 kareyi çözüyor, 900. saniye isteğinde 20 saniye sonra hâlâ yeni görüntü göstermiyordu. Bu makinedeki kısa aktarım ölçümü yaklaşık 20 Mbit/sn idi; bu değer telefonun bağlantı hızını ölçmez.
- Uzak `.mkv` dosyaları VideoLAN'ın `mkv_trusted` demux seçeneğiyle mevcut Cues indeksinden açılır. Aynı dosyada 120., 30., 900. ve 240. saniyelere sarma, yeni görüntü ve süre ilerlemesi dahil **1,98–2,89 saniye** sürdü. İndeksi eksik/bozuk başka dosyalarda aynı süre garanti edilmez.
- VLCKit tek bir sarma tamamlanma callback'i tuttuğu için hızlı istekler birleştirilir, devam eden sarma bitince son hedef uygulanır. Aynı konum ve reddedilen istekler kuyruğu kilitlemez; 30 saniye tamamlanmayan işlem sonsuz bekleme yerine hata durumuna geçer. Kullanıcının duraklatma tercihi korunur.
- Gerçek videoda ileri/geri, aynı anda ve devam eden isteğin üstüne sarma, duraklatılmış videoda aynı konuma/başka konuma geçme ile mevcut oynatıcı testlerinde **20 geçti, 0 hata**. İki eski opt-in başlangıç testi bu koşuya alınmadı; yeni opt-in sağlayıcı sarma testi çalıştı. Kanıt: `build/seek-before-provider-tests.log`, `build/seek-provider-trace.log`, `build/seek-final-tests.log`, `build/seek-provider-diagnostics.json`. Fiziksel iPhone'da bu düzeltme henüz doğrulanmadı.

## 3 Ekim 2026 — kişisel medya paylaşımı

Mağaza incelemesinden seçilen kişisel medya ve bağlantı rehberi özellikleri uygulandı; kapsam ve ertelenen fikirler [ürün planına](PRODUCT_PLAN.md#3-ekim-2026--kişisel-medya-ve-tv-kullanım-deneyimi) eklendi. Fotoğraflar 1080p slayta dönüştürülür, galeri videoları ve ses/video dosyaları ortak oynatıcıya açılır, dosya sırası otomatik ilerler, doğrudan HTTP(S) bağlantısı kaydetmeden oynatılır. Yerel Cast aktarımı yalnız seçilen dosyayı oturum boyunca sunar.

- `build/media-sharing-core.log`: 41 çekirdek + 5 medya testi, sıfır hata. Medya türü ve HTTP Range sınırları dahil.
- `build/media-sharing-scripts.log`: 17 dağıtım aracı testi geçti.
- `build/media-sharing-localization.json`: 22 dil, 247 anahtar, 5.434 değer; sıfır hata.
- `build/media-sharing-regression-5.xcresult`: oynatıcı, TV ve kişisel medya entegrasyon testleri. Slaytın gerçek 1080p video çıktısı, fotoğraf sırası, oynatma, iptal, dosya temizliği, iki ses dosyasının sıralı çalınması, HTTP GET/HEAD/Range, yanlış yolun reddi ve durdurulan adresin kapanması doğrulandı. Sağlayıcı adresi gerektiren üç opt-in test çalıştırılmadı.
- Son kabul koşusu `build/media-sharing-acceptance-2.xcresult`: **6 entegrasyon + 4 UI testi geçti, sıfır hata/atlama**. Sistem seçicisinden iki fotoğraf seçme → düzenleyiciyi kapatma → aynı fotoğrafları yeniden seçme → slaytı oynatma ve duraklatma; fotoğraf seçimini iptal etme; hızlı bağlantıda dosya URL’sini reddetme; bağlantı rehberi ve erişilebilirlikte en büyük yazı boyutu doğrulandı. Yerel HTTP aktarımının CORS/OPTIONS yanıtı da kontrol edildi.
- Son tekrarlarda yakalanan erken dosya temizliği düzeltildi: fotoğraf kopyaları geçici `onDisappear` çağrılarına değil düzenleme oturumunun ömrüne bağlandı. `build/media-sharing-photo-lifetime.xcresult` içinde fotoğraf seçme/oynatma akışı art arda iki kez geçti; ardından yukarıdaki toplu kabul koşusu tamamlandı. İlk PhotosUI hit point ve Türkçe iptal etiketi sorunları test seçicilerinde giderildi. Önceki başarısız raporlar topluca başarılı sayılmaz.
- Cast SDK kaynakları Xcode’un yerel Copy Files adımlarıyla paketlenir; build-script sandbox kapatılmadı. Test komutunun entitlement yolu SwiftPM kaynak hedefleri için mutlak yola çevrildi.

Bunlar simülatör ve yerel doğrulamalardır. Fiziksel iPhone, Google Cast TV, AirPlay TV, araç görüntüsü ve App Store yüklemesi bu çalışmada yapılmadı. 4K/slayt-orijinal-kalite veya yeni TV marka uyumluluğu iddiası yoktur.
