15 Ekim 2026 23:55 — CarTV karşılaştırmasıyla yeni bulgu ve uygulama düzeltmesi: aynı fiziksel iPhone + **Standard** CarPlay Simulator profilinde CarTV 1.1.2, Audio/Video yetkileri birlikteyken sistemin verdiği `UIWindowScene` içine kendi kök görünümünü yerleştiriyor. Önceki “yalnız platform sorunu” değerlendirmesi eksikti. Mirivo artık açık UIScene yaşam döngüsü bildirimlerinden yalnız CarPlay idiom'lu, delegatesiz ve penceresiz sahneyi sahipleniyor; telefon/şablon/harici ekran sahnelerini değiştirmiyor. Bu pencere mevcut ekran yansıtma oynatıcısına bağlandı; bağlantı kesilince pencere ve ekran kaydı bırakılıyor.

Debug **1.0 (20)** iPhone 16 Pro'ya kuruldu ve başlatıldı. Audio ve Video imza değerleri `true`. Standart profilde boş ekran yerine Mirivo ve ekran paylaşımını başlatma açıklaması görsel olarak doğrulandı (`build/deploy/Main-VideoStream-2026-10-15-23-55-02.png`). İki hedefli manifest/sahne seçimi testi geçti (`build/deploy/carplay-window-tests.log`). Kurulum: `build/deploy/carplay-window-install.log`. 23:57’de kullanıcının telefonda başlattığı gerçek ReplayKit ekran paylaşımı standart CarPlay penceresinde canlı gösterildi; iki gözlemde yayın sayacı ilerledi (00:00 → 00:12). Kanıt: `build/deploy/Main-VideoStream-2026-10-15-23-57-31.png`. Bağlantı kesilip yeniden açıldı ve uygulama normal parametrelerle yeniden başlatıldı; Mirivo ekranı tekrar açıldı. EV6 üzerindeki fiziksel kabul henüz yapılmadı. Aşağıdaki eski tanı kayıtları tarihsel karşılaştırmadır.

15 Ekim 2026 23:39 son kurulum: geçici tanı kodları temizlenmiş Debug **1.0 (19)** Audio + Video yetkileriyle iPhone 16 Pro’ya kuruldu ve başlatıldı. Standard Video Playback CarPlay Simulator profilinde ana menü → Kaynaklar → kayıtlı kaynak listesi görsel olarak doğrulandı. Standart profilde boş ekran sorunu açık; video oynatma/EV6 kabulü doğrulanmadı. Kurulum kanıtı: `build/deploy/carplay-final-install.log`.

15 Ekim 2026 23:38 — boş CarPlay ekranı kök neden doğrulaması: iPhone 16 Pro / iOS 27.0, Apple Additional Tools for Xcode 27 içindeki gerçek CarPlay Simulator ile sınandı. Aynı 1.0 (18) ikilisinde kontrollü karşılaştırma: standart araç profili + Audio/Video imzası → boş ekran; yalnız Video entitlement çıkarılarak yeniden imzalanan aynı ikili → Kaynaklar menüsü açılıyor; Audio/Video geri eklenince → tekrar boş ekran. Telefon yeniden başlatmak sorunu gidermedi. Audio/Video imzası, Standard Video Playback araç profilinde menüyü açıyor. Standart profilde sistem `CPTemplateApplicationScene` yerine `UIWindowSceneSessionRoleCarPlay` rolünde delegatesiz `UIWindowScene` yaratıyor; CarPlay callback’leri uygulamaya ulaşmıyor. Bu nedenle önceki sahne yönlendirme değişikliği boş ekranı gidermiş sayılmaz. [Apple DTS aynı hatayı bildiriyor](https://developer.apple.com/forums/thread/843374); bu cihazdaki karşılaştırma ayrı yerel kanıttır.

Kullanıcı **Video yetkisini korumayı** seçti. Audio-only tanı kopyası dağıtım çözümü değildir; standart CarPlay/EV6 boş ekranı halen açık platform uyumluluk sorunudur. Geçici NSLog tanı kodları kaldırıldı. Derlenmiş manifestin sınıfları ve gerçek sistem callback selector’ları için regresyon testi eklendi; iki hedefli sahne testi geçti (`build/deploy/carplay-manifest-tests.log`). Tanı konsolu: `build/deploy/carplay-after-reboot-console.log`, `build/deploy/carplay-scenes-console.log`. App Store Connect/TestFlight bu tanı çalışmasında değiştirilmedi.

15 Ekim 2026 CarPlay görünürlük düzeltmesi: `87329eb` öncesindeki `Config/CarPlay.entitlements` Audio ve Video yetkilerini birlikte içeriyordu. Video geri eklenirken yalnız Video istemek, video desteği bildirmeyen araçlarda simgeyi gizliyordu. Ana uygulama yeniden Audio + Video ister; kaynaklar video desteği olmayan araçlarda ses modunda açılır ve Şu An Çalıyor menüsü geri getirildi. Apple’ın mevcut geliştirme profili iki yetkiyi de içeriyor; portal değişikliği gerekmedi. Debug **1.0 (8)** iPhone 16 Pro'ya kuruldu ve başlatıldı; önceki indirme/TV seçici/yön geçişi düzeltmeleri de bu kurulumda. Gerçek imza ve profil kanıtı: `build/deploy/carplay-visibility-verification.json`; kurulum: `build/deploy/carplay-visibility-install.log`. Araçtaki simgenin ve ses/video çıkışının fiziksel kabulü kullanıcı kontrolünü bekliyor. Bu kurulum yeni bir TestFlight yüklemesi değildir. 26 dağıtım testi, 3 hedefli ses/video geçiş testi ve 22 dil statik kontrolü geçti (`build/deploy/carplay-audio-tests.log`).

# Mirivo iPhone derleme ve dağıtım

15 Ekim 2026 dSYM düzeltmesi: Release **1.0 (17)** saat 20:04 TRT'de TestFlight'a başarıyla yüklendi. Yükleme kaydında **0 `Upload Symbols Failed`**, **0 `warning: exportArchive`** var. 26 dağıtım testi ve 48 Swift testi geçti. Arşiv/IPA imzaları ve CarPlay Video yetkisi doğrulandı. Apple portalındaki ilk durum `Processing`. Kanıt: `build/deploy/testflight-17-{archive,export,upload}.log`, `build/deploy/testflight-17-upload.json`.

dSYM paketleme: `scripts/archive-symbols.mjs`, arşivleme ve mevcut arşivi dışa aktarma sırasında FirebaseAnalytics, GoogleAppMeasurement ve GoogleCast kaynak framework'lerinin Xcode tarafından oluşturulan boş dylib dosyalarını denetler. Yalnız `LC_ID_DYLIB`, sıfır boyutlu `__text` bölümleri ve sıfır sembol doğrulanırsa `dsymutil` ile bu boş dosyanın UUID'sine ait dSYM eklenir; kod içeren bir ikili için eksik üretici sembollerini taklit etmez ve işlemi durdurur. İkili/dSYM UUID ve mimari eşleşmesi zorunludur. Gerçek SDK kodu statik olarak ana uygulamadadır; bu işlem üreticinin sağlamadığı kaynak satırı bilgisini oluşturmaz. Framework kaynakları, gizlilik bildirimleri ve imzalı uygulama değiştirilmez.

İlgili araç zinciri tartışmaları: [Apple Developer Forums](https://developer.apple.com/forums/thread/761589?page=2), [Firebase #13551](https://github.com/firebase/firebase-ios-sdk/issues/13551). Düzeltmenin uygulanabilirliği web yorumlarına göre değil, arşivdeki gerçek Mach-O bölümleri ve sembol tablosuna göre belirlenir.

15 Ekim 2026 TestFlight: Ekran denetimi ve çeviri düzeltmelerini içeren Release **1.0 (16)**, mevcut Xcode Apple hesabıyla 19:34 TRT'de başarıyla yüklendi. Arşiv öncesinde 48 Swift ve 25 dağıtım testi yeniden geçti; 22 dil / 331 anahtar / 7.282 değer statik kontrolden hatasız geçti. Arşiv ve App Store IPA imzaları, CarPlay Video yetkisi ve dağıtım profilleri doğrulandı. Apple işlemesi tamamlandı; Türkçe test notları kaydedildi ve derleme mevcut bir testçili `Mirivo Internal Testers` grubuna eklendi. Grup erişimi TestFlight derleme ekranından doğrulandı. Bu işlem App Review gönderimi veya mağazada yayın değildir.

Yerel dağıtım kayıtları: `build/deploy/testflight-16-{archive,export,upload}.log` ve `build/deploy/testflight-16-upload.json`. FirebaseAnalytics, GoogleAppMeasurement ve GoogleCast için dSYM uyarıları verdi; yükleme başarılı. Sonraki ikili incelemesi, uyarıdaki UUID'lerin gerçek SDK koduna değil Xcode'un sıfır kod/sıfır sembol içeren kaynak framework stub'larına ait olduğunu doğruladı. İlk üretici dSYM eksikliği değerlendirmesi bu üç uyarının nedeni değildi.

15 Ekim 2026: Apple CarPlay Video yetkisini hesaba atadı. İlk geri eklemede yalnız Video entitlement’ı kullanıldı; bu, video desteği bildirmeyen araçlarda simgeyi gizledi. Aşağıdaki güncel imzalama yapılandırması Audio ve Video yetkilerini birlikte kullanır. Developer portalında `com.alperbicer.carmirror` için CarPlay Video etkinleştirildi ve `--allow-provisioning-updates` ile geliştirme profili yenilendi. İmzalı uygulamada Video yetkisi doğrulandı; iPhone 16 Pro’ya yerel ağ üzerinden kurulum ve başlatma başarılı. Gerçek araçta video oynatma henüz doğrulanmadı. Tek scheme `CarMirror`, yapılandırmalar `Debug` ve `Release`.

macOS, Xcode 27, Node.js 22.12+ ve proje üretimi için Ruby xcodeproj gerekir. Yerel takım ayarı `Config/Local.xcconfig` içindeki `DEVELOPMENT_TEAM` ile belirlenir. Var olan dosyayı koru. Gizli anahtarları Git'e ekleme.

Kimlikler: `com.alperbicer.carmirror`, `com.alperbicer.carmirror.broadcast`, `group.com.alperbicer.carmirror`.

15 Ekim doğrulaması: 48 Swift çekirdek testi ve 25 dağıtım testi geçti. Önceki iOS 27 simülatör koşusu başlatma aşamasında tamamlanamadı; mevcut iOS 26.5 simülatöründe aşağıdaki hedefli komutla `CarConnectionReminderTests` içindeki 15 test geçti. Test betiği ortak derleme kilidini, tek derleme işini ve kapalı paralel test ayarını korur. Eksik 438 çeviri değeri tamamlandı; statik yayın kontrolü 22 dilde 327 anahtar ve 7.194 çeviri değeriyle sıfır hata verdi.

```sh
node scripts/test_app.mjs B952AA0F-C81F-49A2-83F3-CEBE9D048739 --only-testing=MirivoTests/CarConnectionReminderTests --keep-cache
```

`--only-testing=TARGET/CLASS/METHOD` ile test seçilebilir; birden fazla seçim için seçenek tekrarlanabilir. `--ui-only` ile birlikte kullanılmaz. Test sonucu `build/app-tests.xcresult` içinde saklanır. Bu koşu gerçek araç ekranında video oynatma doğrulaması değildir.

Aynı gün yapılan sonraki ekran denetiminde hedefli tekrarlar sonunda 22 UI ve 2 uygulama testi geçti; 25 dağıtım betiği testi yeniden geçti. Dört ek metinle güncel katalog 22 dilde 331 anahtar / 7.282 değerdir ve statik kontrol sıfır hata verir. Kapsam ve yerel kanıtlar `docs/RELEASE_ACCEPTANCE.md` içindedir. Test betiği Xcode'un bitişte takılabilen ayrıntılı tanılama toplamasını kapatır; standart `.xcresult` ve ekran ekleri korunur.

Ana uygulama `Config/App.entitlements` ile App Group, APNs, üretim App Attest, CarPlay Audio ve Video kullanır. Uzantı `Config/Broadcast.entitlements` ile yalnız App Group kullanır. İmza doğrulaması yetkileri, profili, kimlikleri, takım ve süreyi denetler; Audio ve Video entitlement’larının hem imza hem profilde bulunmasını zorunlu tutar. Dağıtımda production APNs ve App Store profili gerekir.

```sh
ruby scripts/generate_project.rb --replace
node --test Tests/Scripts/deployment.test.mjs
swift test --jobs 2
bun run mobile:doctor
bun run mobile:devices
bun run check --keep-cache
bun run mobile:ios:simulator --device SIMULATOR_UDID --keep-cache
bun run mobile:ios:install --device IPHONE_UDID --allow-provisioning-updates
bun run mobile:ios:archive --allow-provisioning-updates --keep-cache
bun run mobile:ios:export --archive ARCHIVE_PATH --allow-provisioning-updates
bun run mobile:ios:upload --archive ARCHIVE_PATH --allow-provisioning-updates
```

`--preview` yalnız eski kurulum komutlarıyla uyumlu bir takma addır; kurulumda da CarPlay Video entitlement’ı gerekir. `--keep-cache` kullanılmazsa geçici derleme/bağımlılık önbelleği temizlenir; arşivler, IPA, sonuç kayıtları ve build sayacı korunur. Native komutlar tek kilidi paylaşır. Çalışan komut varken projeyi yeniden üretme veya kilidi silme.

Arşivleme testleri çalıştırır ve build numarasını `build/deploy/last-build.json` üzerinden artırır. `--build` kullanmadan önce App Store Connect'teki en son build'i kontrol et. Var olan `--archive` ile build/sürüm değiştirilemez.

CLI yüklemesi için `.env.deploy` içinde APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID ve APP_STORE_CONNECT_PRIVATE_KEY_PATH gerekir. Anahtar yoksa Xcode Organizer'dan mevcut Apple hesabıyla yükleme yapılabilir. Apple'a yükleme App Review'a gönderim veya yayınlama değildir.

Ekran görüntüleri sentetik demo verisiyle gerçek iPhone arayüzünden alınır. Test sunucusu `python3 scripts/capture_store_screenshots.py`; yalnız 127.0.0.1:8769 dinler. 22 dilde aynı altı ekranın sırası: kaynaklar, kanallar, oynatıcı, paylaşım, Xtream, AirPlay rehberi. Demo uygulamaya paketlenmez.

Netlify paketi `python3 scripts/build_site.py` ile hazırlanır; `python3 scripts/verify_release.py` kaynak/metin/ZIP tutarlılığını denetler. Canlı yayın ayrıca doğrulanır.
