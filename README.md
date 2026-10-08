# Mirivo

Swift ile iPhone ekran paylaşımı ve kişisel medya kaynakları. Görsel kimlik: grafit/mint, kesişen iki ekran ve otomobil simgesi ve üstten iki bölümlü gezinme. Kaynak sürüm **1.0 (8)**; Xcode projesi ve scheme adı `CarMirror` olarak korunur.


## Uygulama

- ReplayKit ekranı ve uygulama sesi → H.264/AAC → bellekte sınırlı HLS yayını. Dengeli 540p/20 fps ve yüksek 720p/30 fps; görüntüyle ses veya kaynak uygulamanın sesini koruma seçeneği.
- M3U, doğrudan yayın ve Xtream Codes kaynakları, kanal/grup arama, yerel oynatıcı ve büyük kontrollü araç modu. Kaynak altyazıları sistem oynatıcısından seçilir.
- Fotoğraf seçimiyle 1080p slayt gösterisi (3/5/8 saniye), galeriden video, iPhone/iCloud Drive’dan ses ve video dosyaları, otomatik oynatma sırası ve kaydetmeden bağlantı açma. Kişisel dosyalar geçici kopyalarla işlenir; Google Cast için yalnız oynatılan dosyayı sunan, durdurunca kapanan yerel aktarım kullanılır.
- Ana ekranda kişisel medya kartları, Google Cast/AirPlay bağlantı rehberi ve bağlantı sorunlarında ayarlara geçiş. Fiziksel TV uyumluluğu ayrıca doğrulanmalıdır.
- iOS 26 ve desteklenen cihaz/dillerde SpeechAnalyzer ile cihaz içi canlı altyazı. Dil modeli önceden hazırlanır; altyazı yayın görüntüsüne eklenir.
- 22 dilde arayüz ve aranabilir dil seçimi; Arapça/İbranice için sağdan sola düzen; Türkçe/İngilizce yasal sayfalar ve yardım; teknik rapor paylaşımı/temizleme; bütün kaynakları ve giriş bilgilerini silme.
- StoreKit 2 ile yıllık abonelik ve tek ödemelik Pro. Satış ekranı açık; RevenueCat işlem gözlemleme entegrasyonu Apple SDK anahtarıyla etkinleşir. **Hiçbir sürümde reklam yok.** Fiyatlar kodda sabitlenmez. [Pro hazırlığı](docs/PRO_RELEASE.md).
- Firebase Remote Config ile zorunlu güncelleme ve izinle açılan FCM bildirim altyapısı. Ağ/politika hatasında uygulama açık kalır. Varsayılan genel duyuru aboneliği ücretsiz Spark planında çalışır; cihaza özel kayıt için isteğe bağlı Cloud Functions sunucusu da hazırdır. Canlı Firebase/Apple kurulumu ve doğrulama adımları: [Firebase kurulumu](docs/FIREBASE_SETUP.md).


## Geliştirme ve kontroller

Xcode 27, Swift ve `xcodeproj` Ruby gem'i kullanılır. Minimum hedef iOS 18. `Config/Local.xcconfig.example` yerel takım ayarları içindir.

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


Projeyi testler veya derleme çalışırken yeniden üretme. Testler için tek simülatör kullan; bellek kısıtlı bilgisayarda başka bir native derlemeyle eşzamanlı çalıştırma.

## Kurulum ve imzalama

`CarMirror` scheme’i `Config/App.entitlements` kullanır. Uygulama App Group, Push Notifications ve App Attest; yayın uzantısı App Group ister. Bu sürüm CarPlay sahnesi, Audio/Video yetkisi veya CarPlay menüsü içermez. Eski CarPlay arşivleri dağıtım kontrollerinde reddedilir.

```sh
bun run mobile:doctor
bun run mobile:devices
bun run check
bun run mobile:ios:preview
bun run mobile:ios:install --device 'IPHONE_UDID' --allow-provisioning-updates
bun run mobile:ios:testflight --allow-provisioning-updates
```


## Veri ve web teslimi

Kaynak adresleri ve giriş bilgileri Keychain'de; kaynak adları ve ayarlar cihazda saklanır. Yayın, ses ve altyazı geçici bellekte işlenir. Durdurunca oturum adresi geçersizleşir. Kayıtlar en fazla 10 oturum / 5 MiB tutar; içerik, adres ve parola içermez. Raporu kullanıcı paylaşır.

[Mirivo destek sitesi](https://mirivo-support.netlify.app) 3 Ekim 2026’da Netlify’da yayımlandı. `Release/mirivo-netlify.zip` yeniden manuel yükleme içindir; `index.html` ZIP kökündedir. Gizlilik, EULA ve yardım Türkçe/İngilizce hazırlanmıştır. Uygulamadaki gizlilik, EULA ve yardım bağlantıları doğrudan Netlify sayfalarını açar; uygulama paketinde belge HTML kopyaları yoktur. SDK lisans bildirimleri `Resources/Notices` altında korunur. Destek: **alperrbicer@gmail.com**. [Yükleme adımları](Release/README.txt).

[22 dilin kapsamı ve doğrulaması](docs/LOCALIZATION.md), [Ürün planı](docs/PRODUCT_PLAN.md), [fiziksel kabul ölçütleri](docs/RELEASE_ACCEPTANCE.md), [seçilen tasarım](Design/mirivo.html).
