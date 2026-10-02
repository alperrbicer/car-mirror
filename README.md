# CarMirror

Hedef, iPhone 16 Pro ekranını 2024 Kia EV6'nın orijinal ekranına CarPlay üzerinden
yansıtmaktır. Uygulama araç ekranındaki kendi simgesinden açılmalıdır.

**Bu hedef henüz tamamlanmadı.** Telefonda başlayan ReplayKit yayını, araç ekranına
görüntü ulaştığı anlamına gelmez. Kurulu `0.1.0 (2)` sürümü CarPlay yetkileri
olmayan eski derlemedir; araçta simgesinin görünmemesi bu kurulumun eksikliğidir.

## Doğrulanan CarTV farkı

2 Ekim 2026'da eşlenmiş iPhone'un InstallationProxy hizmetinden yalnızca uygulama
kurulum bilgileri okundu. CarTV'nin uygulama dosyaları veya kullanıcı verileri
okunmadı.

| Kurulu uygulama | Bundle ID | CarPlay Audio | CarPlay Video |
| --- | --- | --- | --- |
| CarTV 1.1.1 (35) | `com.lyntra.player` | Var | Var |
| CarMirror 0.1.0 (2) | `com.alperbicer.carmirror` | Yok | Yok |

CarTV'nin sahne bildirimi bir `CPTemplateApplicationScene` ve iki harici ekran
rolü içeriyor: `UIWindowSceneSessionRoleExternalDisplay` ve
`UIWindowSceneSessionRoleExternalDisplayNonInteractive`. Bu bildirimler, CarTV'nin
CarPlay üzerinde görüntüyü hangi kodla çizdiğini açıklamıyor. CarTV ile aynı
aktarım yöntemi uygulandığı iddia edilmiyor.

Yerel kanıt: `build/app-signing-metadata.json`. Bu geçici dosya Git'e dahil değil.

## İmzalama

Ana uygulamanın **bütün** Debug/Release yapılandırmaları artık
`Config/CarPlay.entitlements` kullanır ve şu yetkileri ister:

- `com.apple.developer.carplay-audio`
- `com.apple.developer.carplay-video`
- `group.com.alperbicer.carmirror` App Group erişimi

Yayın uzantısı yalnızca App Group yetkisini ister. `CarMirror` ve önceki
`CarMirror CarPlay` scheme'i aynı CarPlay yetkilerini gerektirir. CarPlay
imzalaması başarısız olduğunda telefona sessizce yetkisiz bir sürüm kuran ayrı
bir yapılandırma yoktur.

Ses ve video yetkileriyle otomatik provisioning denendi. Xcode iki yetkinin de
profile eklenemediğini bildirdi; bu derleme imzalanamadı ve telefona kurulmadı.
Bir entitlement'ı kaynak dosyaya yazmak, imzalı profile eklemez. Chrome üzerinden
Apple Developer portalındaki `com.alperbicer.carmirror` kaydı kontrol edildi:
CarPlay yetkileri etkin değil. CarPlay Audio App, Capability Requests altında
başvuru bağlantısıyla görünüyor. Video seçeneği CarPlay başvuru formunda var;
ilerlemek için CarPlay Entitlement Addendum sözleşmesinin kabulü isteniyor.
Kullanıcı sözleşme adımını tamamladı. Chrome'da “Thank you for your submission”
ve Apple'ın başvuruyu inceleyip durum güncellemesi ileteceği mesajı doğrulandı.
Bu, başvurunun alındığına dair kanıttır; yetkinin verildiği anlamına gelmez.
Başvurudan sonra uygulama kimliği sayfası yenilenerek kontrol edildi; CarPlay
yetkileri henüz kullanılabilir yetkiler listesine eklenmemişti.
Yerel ekran kaydı: `build/carplay-request-submitted.jpg`.

Apple'ın CarPlay açıklamasına göre video yetkisi tek başına uygulamanın yalnızca
video destekli araçlarda görünmesini sağlar; uygun ses ve video uygulamaları iki
yetkiyle bütün CarPlay araçlarında görünebilir. **Simgenin görünmesi, video
aktarımının çalıştığını kanıtlamaz.**

## Mevcut kod

- SwiftUI ana ekranında paylaşımı başlatma/durdurma, araçta oynatma ve bağlantı
  durumu bulunur. AirPlay hedef seçimi, telefon önizlemesi, prototip rozeti ve uzun
  kullanıcı bilgilendirme bölümleri kaldırıldı.
- ReplayKit Broadcast Upload Extension ekran karelerini alır.
- AVAssetWriter, 960 × 540 çözünürlükte en fazla 20 fps H.264/fMP4 üretir.
- Network.framework sunucusu bellekteki kayan HLS listesini sağlar.
- CarPlay sahnesi `CPSessionConfiguration.supportsVideoPlayback` ve
  `CPPlaybackConfiguration` ile Apple'ın video oynatma yolunu kullanır.
- `AVPlayer` harici video oynatımı için yerel ağ adresini kullanır.

Son iki adım, EV6 üzerinde çalışan CarTV yönteminin doğrulanmış karşılığı
**değildir**. CarTV'nin ilan ettiği Wi-Fi gerektirmeyen doğrudan CarPlay aktarımı
henüz bu projede uygulanmış ve araçta doğrulanmış değildir.

Video hattı yalnızca görüntüyü kodlar. Kaynak uygulamanın sesi yeniden kodlanmaz.
Kaynak uygulamaya geçildiğinde sesin ve araç görüntüsünün devam etmesi fiziksel
cihaz ve araç testi gerektirir.

## Geliştirme

`CarMirror.xcodeproj` dosyasını Xcode 27 ile aç. Minimum iOS sürümü 18'dir;
CarPlay Video API'leri iOS 26.4 kullanılabilirlik kontrolüyle çağrılır.
`Config/Local.xcconfig.example` üzerinden yerel takım kimliğini ayarla.

```sh
swift test --jobs 2

xcodebuild -project CarMirror.xcodeproj -scheme CarMirror \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project CarMirror.xcodeproj -scheme CarMirror \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/iPhone -allowProvisioningUpdates build
```

İmzasız derleme, telefon kurulumu veya araç testi yerine geçmez. Proje üreticisi:
`ruby scripts/generate_project.rb --replace` (`xcodeproj` Ruby gem'i gerekir).

## Yayın verisi

Kareler ve video bölümleri diske veya buluta kaydedilmez. Tampon en fazla 8 MiB
ve 10 bölüm tutar; oynatma listesi son 6 bölümü sunar. Oturum adresi rastgele
üretilir ve yayın durunca geçersiz olur. HTTP sunucusu hücresel arayüzleri
kullanmaz. App Group'ta durum ve durdurma komutu tutulur; 6 saniyelik heartbeat
süresi geçen oturum canlı kabul edilmez.

## Doğrulama kaydı

- Önceki kaynak sürümünde 8 çekirdek + 2 medya testi geçti. Medya testi gerçek
  H.264 üretimini/çözümünü ve HTTP erişimini denetledi; araç testi yapmadı.
- Kurulu build 2'nin CarPlay yetkileri olmadığı cihazdan doğrulandı.
- İki CarPlay yetkisiyle imzalama başarısız: `build/build-carplay-audio-video-signing.log`.
- Güncellenen ana yapılandırmanın simülatör ve imzasız iPhone derlemeleri geçti.
  iPhone kaynak derlemesinin günlüğü: `build/build-carplay-required-device.log`.
- Kaynak build numarası 3; bu değişiklikler henüz telefona kurulmadı.
- Kullanıcı CarTV ile araçta görüntü aldığını; CarMirror ile yayının başladığını,
  ancak araçta simge ve görüntü olmadığını bildirdi.

## Kaynaklar

- [Apple: CarPlay uygulamaları, ses/video yetkileri ve araç desteği](https://developer.apple.com/videos/play/wwdc2026/212/)
- [Apple: CarPlay yetkisi isteme](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
- [CarTV: ekran yansıtma açıklaması](https://cartv.app/)

## Hazır kurulum ve yayın komutları

Cihaz seçimi, iPhone/simülatör kurulumu, Release arşivi, IPA ve TestFlight
komutları bu repodaki `package.json` ve `scripts/ios.mjs` içindedir.
Kurulum ayarları ve tüm seçenekler: [Kurulum ve yayın kılavuzu](docs/DEPLOYMENT.md).

```sh
bun run mobile:doctor
bun run mobile:devices
bun run check
bun run mobile:ios:install --device 'IPHONE_UDID' --allow-provisioning-updates
bun run mobile:ios:testflight --allow-provisioning-updates
```

Önce yapılacak işlemleri görmek için komuta `--dry-run` ekle. İmzalı cihaz
kurulumu ve mağaza yüklemesi, ana uygulamanın CarPlay Audio/Video yetkilerini ve
uygulama/uzantı profillerindeki App Group erişimini gerektirir.
