# Mirivo

Swift ile iPhone ekran paylaşımı ve kişisel medya kaynakları. Görsel kimlik: **Mirivo + A**, grafit/mint ve otomobilli iki ekran logosu. Kaynak sürüm **1.0 (6)**; Xcode projesi ve scheme adı `CarMirror` olarak korunur.

İlk fiziksel hedef iPhone 16 Pro ve 2024 Kia EV6'dır. **Araçta görüntü ve ses henüz doğrulanmadı.** Apple CarPlay yetkili profili, fiziksel kabul, TestFlight ve App Review açık. Güncel yerel sonuçlar ve önceki portal kanıtları [uygulama durumunda](docs/IMPLEMENTATION_STATUS.md) ayrı tutulur.

## Uygulama

- ReplayKit ekranı ve uygulama sesi → H.264/AAC → bellekte sınırlı HLS yayını. Dengeli 540p/20 fps ve yüksek 720p/30 fps; görüntüyle ses veya kaynak uygulamanın sesini koruma seçeneği.
- M3U, doğrudan yayın ve Xtream Codes kaynakları, kanal/grup arama, yerel oynatıcı ve büyük kontrollü araç modu. Kaynak altyazıları sistem oynatıcısından seçilir.
- iOS 26 ve desteklenen cihaz/dillerde SpeechAnalyzer ile cihaz içi canlı altyazı. Dil modeli önceden hazırlanır; altyazı yayın görüntüsüne eklenir.
- CarPlay video desteğine bağlı ekran paylaşımı ve kaynak listesi; iOS gerçekten harici ekran sahnesi sağladığında ortak oynatıcı.
- Türkçe/İngilizce arayüz, yasal sayfalar ve yardım; teknik rapor paylaşımı/temizleme; bütün kaynakları ve giriş bilgilerini silme.
- StoreKit 2 ile haftalık, yıllık ve tek ödemelik Pro hazırlığı. **Satış kapalı; mevcut özellikler ücretsiz. Hiçbir sürümde reklam yok.** Fiyatlar kodda sabitlenmez. [Pro hazırlığı](docs/PRO_RELEASE.md).

CarTV'nin kurulu sürümünde Audio/Video yetkileri ve harici ekran bildirimleri görüldü. Bu bulgu, uygulamanın iç aktarım yöntemini açıklamaz; Mirivo'nun aynı teknikle çalıştığı veya EV6 uyumluluğunun kanıtlandığı iddia edilmez.

## Geliştirme ve kontroller

Xcode 27, Swift ve `xcodeproj` Ruby gem'i kullanılır. Minimum hedef iOS 18; resmî CarPlay video API'leri iOS 26.4 kullanılabilirlik kontrolündedir. `Config/Local.xcconfig.example` yerel takım ayarları içindir.

```sh
ruby scripts/generate_project.rb --replace
swift test --jobs 2
node --test Tests/Scripts/deployment.test.mjs
python3 scripts/build_site.py
python3 scripts/verify_release.py
node scripts/test_app.mjs SIMULATOR_UDID
# Yalnız arayüz testleri:
node scripts/test_app.mjs SIMULATOR_UDID --ui-only
```

Son Swift çalışmasında 23 çekirdek ve 5 gerçek medya testi; kurulum araçlarında 14 test geçti. Ses/video testleri araç testi yerine geçmez. Satın alma ve arayüz testlerinin ayrı durumları [doğrulama kaydında](docs/IMPLEMENTATION_STATUS.md) bulunur. `.storekit` fiyatları yalnızca yerel test verisidir; dosya uygulamaya paketlenmez.

Projeyi testler veya derleme çalışırken yeniden üretme. Testler için tek simülatör kullan; bellek kısıtlı bilgisayarda başka bir native derlemeyle eşzamanlı çalıştırma.

## Kurulum ve imzalama

Ana uygulama `Config/CarPlay.entitlements` ile CarPlay Audio, Video ve App Group ister. Uzantı yalnız App Group ister. Kimlikler `com.alperbicer.carmirror`, `.broadcast` ve `group.com.alperbicer.carmirror` olarak korunur.

```sh
bun run mobile:doctor
bun run mobile:devices
bun run check
bun run mobile:ios:preview
bun run mobile:ios:install --device 'IPHONE_UDID' --allow-provisioning-updates
bun run mobile:ios:testflight --allow-provisioning-updates
```

`preview` yalnız iPhone arayüzü için CarPlay yetkilerini kaldırır; App Group ve imza/profil kontrollerini korur. Önizlemede CarPlay simgesi veya araç yansıtması beklenmez; arşiv/IPA/TestFlight komutları bu seçeneği reddeder. Son doğrulanan telefon kurulumu 0.1.0 (4) önizlemesidir; build 6 fiziksel telefona yüklenmedi. [Kurulum kılavuzu](docs/DEPLOYMENT.md).

## Veri ve web teslimi

Kaynak adresleri ve giriş bilgileri Keychain'de; kaynak adları ve ayarlar cihazda saklanır. Yayın, ses ve altyazı geçici bellekte işlenir. Durdurunca oturum adresi geçersizleşir. Kayıtlar en fazla 10 oturum / 5 MiB tutar; içerik, adres ve parola içermez. Raporu kullanıcı paylaşır.

`Release/mirivo-netlify.zip` Netlify'a manuel yükleme içindir; `index.html` ZIP kökündedir. Gizlilik, EULA ve yardım Türkçe/İngilizce hazırlanmıştır. Aynı belgeler `Resources/Legal` altında çevrimdışı açılır. Destek: **alperrbicer@gmail.com**. [Yükleme adımları](Release/README.txt).

[Ürün planı](docs/PRODUCT_PLAN.md), [fiziksel kabul ölçütleri](docs/RELEASE_ACCEPTANCE.md), [seçilen tasarım](Design/mirivo.html).
