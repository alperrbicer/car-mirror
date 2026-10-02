# Mirivo · 2 Ekim 2026

Kaynak sürüm **1.0 (6)**. Mirivo + A grafit/mint kimliği ve otomobilli iki ekran logosu korunuyor. Bu sürümün yerel uygulaması ve yayın hazırlığı aşağıda kayıtlıdır. EV6'da görüntü ve ses, CarPlay yetkili kurulum, TestFlight ve App Review henüz doğrulanmadı.

## Uygulanan ürün kapsamı

- Yansıt, Kaynaklar ve Ayarlar sekmeleri; kısa açılış geçişi, koyu tema, büyük yazı ve Hareketi Azalt desteği. Standart, koyu ve renklendirilmiş ikonlar aynı logo geometrisini kullanır.
- M3U, doğrudan yayın ve Xtream Codes kaynakları; kanal/grup arama, kaynak silme, yerel oynatıcı, kaynak altyazıları ve büyük kontrollü araç modu. Kaynak adresleri ve hesap bilgileri Keychain'de, kaynak adları cihazda saklanır. İçerik veya IPTV hesabı sağlanmaz.
- ReplayKit ekranı ve uygulama sesi, aynı zaman tabanında H.264/AAC yayınına dönüştürülür. Dengeli 960×540/20 fps ve yüksek 1280×720/30 fps seçenekleri vardır. Ses, görüntüyle taşınabilir veya kaynak uygulamanın ses yolu korunabilir. Araçtaki senkron ve çift ses davranışı ayrıca ölçülecek.
- iOS 26 ve desteklenen cihaz/dilde SpeechAnalyzer ile cihaz içi canlı altyazı. Dil modeli ayarlardan hazırlanır; geçici altyazı videoya eklenir. Ses ve döküm dosyaya veya geliştirici sunucusuna gönderilmez. Gerçek yayın uzantısının bellek ve konuşma kabul testi açık.
- CarPlay listesinde ekran paylaşımı ve kaynak kitaplığı bulunur. Video eylemleri sistemin video desteği bildirimine bağlıdır. Uzun kanal listeleri aynı sayfa üzerinde ilerler; CarPlay gezinme yığını büyümez. Gerçek harici ekran sahnesi sağlanırsa ortak oynatıcı kullanılır.
- Oturum kimliği, eski bildirimler, duraklama, kesinti, yeniden deneme, zaman aşımı, durdurma ve temizleme işlenir. Ekran yakalamanın başlaması tek başına araçta görüntü var sayılmaz.
- Son 10 oturum / toplam 5 MiB sınırında teknik kayıt, rapor paylaşımı ve kayıt silme. URL, parola, erişim anahtarı, ekran, ses, altyazı ve cihaz adı rapora yazılmaz; rapor otomatik gönderilmez.
- Haftalık, yıllık ve tek ödemelik Pro için StoreKit 2 ürün yükleme, doğrulanmış erişim, satın alma, geri yükleme, işlem güncellemeleri, iade ve sona erme akışları hazırlandı. **Satış kapalıdır; mevcut özellikler ücretsizdir ve hiçbir sürümde reklam yoktur.** Gerçek fiyatlar daha sonra App Store Connect'ten gelecek.
- Türkçe/İngilizce uygulama metinleri; dil, kalite, ses, altyazı ayarları; çevrimdışı gizlilik/EULA/yardım sayfaları; destek adresi `alperrbicer@gmail.com`. Kullanıcının son istediği 22 dil, bu önceki işlerin doğrulamasından sonra ele alınacak.

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
| Swift çekirdek ve medya | **28 geçti**: 23 çekirdek, 5 medya. Gerçek H.264/AAC üretimi ve çözümü, kaynak sesin varlığı, zaman çizgisi, HTTP erişimi, tampon sınırları, 10 kez durdurma, kaynak ayrıştırma ve kayıt mahremiyeti. `build/production-swift-final.log` |
| Kurulum araçları | **14 geçti**. Önizleme/CarPlay ayrımı, kimlik/profil, cihaz seçimi ve başarısız derleme sonrası kurulumu durdurma dahil. `node --test Tests/Scripts/deployment.test.mjs` |
| Site ve yerelleştirme | 12 HTML, 175 Türkçe/İngilizce anahtar, çevrimdışı kopyalar, bağlantılar, plist'ler, satışın kapalı olması ve ZIP içerik eşleşmesi geçti. `build/release-static-checks.json` |
| Debug uygulama derlemesi | **Başarılı**: `build/production-ui-final.log` ve son CarPlay değişikliğini içeren `build/production-landscape-final.log`. |
| Release cihaz derlemesi | **Başarılı**: `build/production-release-accessibility.log`. Uygulama/uzantı 1.0 (6), satış bayrağı NO; test StoreKit dosyası dağıtım paketinde yok. İmzasız derleme, fiziksel kurulum veya dağıtım sonucu değildir. |
| Uygulama/arayüz testleri | **2 akış geçti**: Türkçe kaynak ekleme/silme, ücretsiz Pro, çevrimdışı gizlilik/EULA/yardım; İngilizce büyük yazı ve yatay etkileşim. `build/production-ui-final.xcresult`. Yatay etkileşim ve en büyük yazı boyutunda kaydırılan paylaşım/durum alanı son değişiklikle `build/production-unlocked-qa.xcresult` üzerinden geçti; iki ekran görüntüsü ayrıca incelendi. Pro, ayarlar ve gizlilik ekranları görsel olarak incelendi. Önceki Keychain kaydet/oku/sil testi de geçti. |
| StoreKit | **Doğrulanamadı**: iOS 26.5 test ortamı `SKInternalErrorDomain Code=3` / `notEntitled` verdi. İki iOS 27 denemesinde test oturumu başlamadı; bellek baskısı nedeniyle denemeler durduruldu. `build/production-qa27-resumed.log`, `build/production-storekit-final.log`. Satın alma, geri yükleme, iade ve abonelik bitişi geçmiş sayılmıyor; satış açılmadan önce bu testler ve gerçek sandbox senaryoları tamamlanacak. |

Ses/video testinde iki iz 0'dan başladı; ses 3,967 sn, video 4,010 sn sürdü. Bu yerel kodlama kanıtıdır; araç gecikmesini veya EV6 ses rotasını ölçmez.

## Apple ve fiziksel cihaz durumu

Son portal kontrolü 2 Ekim 2026'daki önceki Chrome çalışmasına aittir; bu çalışmada Chrome açılmadı.

- Takım `3T2VY64864`; ana uygulama `com.alperbicer.carmirror`; uzantı `.broadcast`; App Group `group.com.alperbicer.carmirror`.
- CarPlay Video ve Audio taleplerinde Apple alındı mesajı gösterdi. Yetki onayı veya geçerli ana uygulama CarPlay profili doğrulanmadı.
- [Mirivo App Store Connect kaydı](https://appstoreconnect.apple.com/apps/6818560405/distribution/info): `6818560405`, SKU `mirivo-ios`, Türkçe ana dil, iOS 1.0 taslağı. Binary veya inceleme gönderimi yapılmadı.
- Telefona en son kurulduğu doğrulanan sürüm **0.1.0 (4) iPhone önizlemesi**; CarPlay yetkileri yok. Build 6 bu çalışma sırasında fiziksel telefona kurulmadı.
- CarTV 1.1.1 (35) kurulum bildiriminde Audio/Video yetkileri ve harici ekran rolleri görüldü. Bu bilgi CarTV'nin iç aktarım tekniğinin çözüldüğü anlamına gelmez.

Apple yetkileri ve gerçek imzadan sonra iPhone 16 Pro + 2024 Kia EV6'da kablo ve markasız adaptör ayrı sınanacak. YouTube ve Smarters Player ile görüntü/ses, 30 dakikalık kullanım, 10 başlat/durdur, kesinti, yön değişimi ve altyazı belleği ölçülecek. Bunlar tamamlanmadan ürünün production kabulü kapatılmaz.
