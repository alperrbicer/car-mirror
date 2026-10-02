# Mirivo · 2 Ekim 2026

Devam noktası ve bütün açık işler: [NEXT_STEPS.md](NEXT_STEPS.md).

Kaynak sürüm **1.0 (6)**. Mirivo + A grafit/mint kimliği ve otomobilli iki ekran logosu korunuyor. Bu sürümün yerel uygulaması ve yayın hazırlığı aşağıda kayıtlıdır. EV6'da görüntü ve ses, CarPlay yetkili kurulum, TestFlight ve App Review henüz doğrulanmadı.

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

- `Release/mirivo-netlify.zip`: Türkçe/İngilizce 12 HTML sayfası, stil, logo ve Netlify başlık/yönlendirme dosyaları. ZIP kökünde `index.html` bulunur. Kullanıcı yayımlayacak; bu çalışma Netlify'a yükleme yapmadı.
- `Release/README.txt`: yükleme ve mağazaya girilecek URL yolları.
- `Release/AppStore/{tr,en}/metadata.json`: mağaza metinleri; `review-notes.txt` ve `privacy-inventory.json`: inceleme/veri hazırlığı. Portalda yüklenmiş oldukları iddia edilmiyor.
- `Resources/Legal`: uygulamada internet olmadan açılan aynı belgeler. Hayali alan adı veya destek formu kullanılmaz.
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
