# CarMirror — ilk Swift prototipi

Xcode projesi: `CarMirror.xcodeproj`. Kaynaklar bu klasörde. iPhone uygulaması
SwiftUI, ekran yakalama uzantısı ReplayKit, video hattı AVFoundation ve yerel HTTP
sunucusu Network.framework kullanır. Haricî uygulama/kütüphane bağımlılığı yoktur.

## Bu sürümün kapsamı

- iOS'un gerçek ekran yayını düğmesi ve kullanıcı onayı.
- Başka uygulamalara geçildiğinde çalışması için Broadcast Upload Extension.
- En son ekran karesinden 960 × 540, en fazla 20 fps H.264 video üretimi.
- Dikey/yatay ekranı kırpmadan sabit yatay görüntüye sığdırma.
- Birer saniyelik fMP4 bölümleriyle kayan HLS listesi; yaklaşık birkaç saniye gecikme.
- Telefon üzerinde canlı önizleme.
- CarPlay Video sahnesi, video destek sorgusu ve `CPPlaybackConfiguration`.
- Yayın, araç bağlantısı ve harici oynatma için ayrı durum göstergeleri.
- Kullanıcı durdurduğunda oturum adreslerini iptal etme ve belleği boşaltma.

Bu, **CarTV ile aynı araçlarda çalıştığı kanıtlanmış bir uygulama değildir**.
CarTV'nin araç ekranına görüntü çizme yöntemi bilinmiyor. Burada herkese açık
CarPlay Video / AirPlay yolu uygulanmıştır. Aracın CarTV'yi çalıştırması,
`supportsVideoPlayback` değerinin bu uygulamada `true` olacağını kanıtlamaz.

İlk sürüm **yalnızca görüntüyü** kodlar. YouTube/IPTV sesinin mevcut araç ses
rotasında kalması hedeflenir; ses tekrar yakalanmaz ve tekrar oynatılmaz.
Kaynak uygulamayla eşzamanlı kullanım ve ses davranışı fiziksel cihaz testidir.
DRM/FairPlay korumalı içerikler yakalamada siyah görünebilir. Koruma aşılmaz.

## Xcode ile açma

Depo klasöründe çalıştır:

```sh
open CarMirror.xcodeproj
```

Proje Xcode 27 SDK'sıyla hazırlanmıştır. Minimum telefon sürümü iOS 18'dir.
CarPlay Video API'leri kullanılabilirlik kontrolüyle iOS 26.4 ve üstünde çağrılır.
ReplayKit, iOS 18 uyumluluğu için kullanılır; iOS 27 SDK'sında bazı yakalama
API'leri deprecated işaretlidir. Yeni ScreenCaptureKit yoluna geçiş ayrı iştir.

İki scheme vardır:

| Scheme | Amaç | Gerekli yetki |
| --- | --- | --- |
| `CarMirror` | Telefonda ekran yakalama ve önizleme | App Groups |
| `CarMirror CarPlay` | Aynı yayın + resmî CarPlay Video sahnesi | App Groups + Apple onaylı CarPlay Video |

Normal scheme'in araçta uygulama simgesi göstermesi beklenmez. CarPlay scheme'i
seçmek Apple'ın yetki onayını sağlamaz; yetki imzalı provisioning profile'da da
bulunmalıdır. Başka uygulama kategorilerinin yetkileri kullanılmaz.

## Fiziksel telefonda hazırlık

1. Xcode'da ana uygulama ve `CarMirrorBroadcast` hedeflerine kendi geliştirici
   takımını seç. İstersen `Config/Local.xcconfig.example` dosyasını
   `Config/Local.xcconfig` olarak kopyalayıp takım kimliğini oraya yaz.
2. Varsayılan kimlikler `com.alperbicer.carmirror`,
   `com.alperbicer.carmirror.broadcast` ve `group.com.alperbicer.carmirror`.
   `MIRROR_BUNDLE_ID` değişirse diğer kimlikler aynı ayardan türetilir.
3. İki hedefin aynı App Group'u kullandığını ve profillerin bu grubu içerdiğini
   doğrula. Ekran yayını için ayrı bir hayalî ReplayKit entitlement ekleme.
4. Önce normal `CarMirror` scheme'ini fiziksel iPhone'a yükle.
5. Sistem yayın düğmesinden CarMirror'ı seçip başlat. Birkaç saniye sonra
   önizleme kullanılabilir olmalı. Başka uygulamaya geç, ardından geri dönerek
   alınan kare ve bölüm sayılarının ilerlediğini kontrol et.
6. Araç testi için Apple'dan CarPlay Video yetkisi al, App ID ve profili güncelle,
   sonra `CarMirror CarPlay` scheme'ini imzala. Uygulama araçta açılırsa “iPhone
   ekranı” satırından oynatmayı başlat; ardından telefonda kaynak uygulamayı aç.

2 Ekim 2026'da normal scheme Xcode'un otomatik provisioning akışıyla imzalandı
ve iPhone 16 Pro'ya kuruldu. CarPlay entitlement başvurusu ve App Store yüklemesi
yapılmadı. CarPlay sürümünün imzalama sonucu aşağıdaki doğrulama bölümündedir.

## Aktarım ve erişim sınırları

```text
iOS ekran yayını onayı
  → ReplayKit uzantısı
  → H.264 / fMP4 kodlayıcı
  → sınırlı bellek tamponu + yerel HTTP
  → AVPlayer
  → desteklenen CarPlay Video / AirPlay alıcısı
```

- Ekran kareleri ve video bölümleri diske veya buluta kaydedilmez.
- HLS tamponu en fazla 8 MiB ve 10 bölüm tutar; oynatma listesi son 6 bölümü
  sunar. Kodlayıcı yalnızca en son gelen kaynak karesini tutar.
- Her oturumda rastgele bir erişim yolu oluşturulur. Sunucu yalnızca bu yoldan
  `GET` ve `HEAD` medya isteklerini kabul eder; dosya sistemi sunucusu değildir.
- Yayın **yerel HTTP** kullanır, TLS şifrelemesi içermez. Adresi bilen aynı ağdaki
  bir alıcı yayını çekebilir. Gizli adres günlüklerde veya arayüzde gösterilmez.
- Hücresel arayüzde dinleme engellenir. Bu sunucuya bir internet tüneli veya
  port yönlendirme eklenmemelidir.
- App Group'ta sadece durum, sayaçlar, geçici URL'ler ve durdurma komutu bulunur.
  Bu küçük dosyalar yedeklemeye dahil edilmez; normal durdurmada URL'ler temizlenir.
- Ani süreç sonlanması durumunda heartbeat 6 saniye sonra bayatlar. Arayüz eski
  bir oturumu canlı saymaz; yeniden başlatılan yayın yeni adres kullanır.
- Araç alıcısının telefonun yerel IP'sine ulaşması gerekir. `127.0.0.1` sadece
  telefon önizlemesinde kullanılır. LAN adresi yoksa araç oynatımı başlatılmaz.
- Kablolu CarPlay, kablosuz CarPlay ve farklı multimedya sistemlerinin adresi
  gerçekten çekebilmesi henüz doğrulanmamıştır. CarTV'nin “Wi-Fi gerekmiyor”
  davranışının bu prototipte sağlandığı iddia edilmez.
- Araç hareket/oynatma politikasını işletim sistemi uygular. `supportsVideoPlayback`
  tek başına “araç parkta” veya “video şu anda ekranda” anlamına gelmez.

## Kontroller

```sh
swift test --jobs 2

xcodebuild \
  -project CarMirror.xcodeproj \
  -scheme CarMirror \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  build

xcodebuild \
  -project CarMirror.xcodeproj \
  -scheme 'CarMirror CarPlay' \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/Device \
  CODE_SIGNING_ALLOWED=NO build
```

Swift paket testleri macOS'ta HLS penceresini, bellek sınırını, durdurma sonrası
erişim iptalini, HTTP byte-range yanıtlarını ve taze/bayat oturum ayrımını kontrol
eder. Medya testi tek bir sabit görüntüden gerçek H.264 bölümleri üretir, tekrar
decode eder ve dikey görüntünün kenar boşluklarını denetler. Bu testler iPhone'un
ReplayKit callback'lerinin veya fiziksel CarPlay ekranının kanıtı değildir.

Proje dosyasını yeniden oluşturmak gerekirse `ruby scripts/generate_project.rb
--replace` çalıştırılır (`xcodeproj` Ruby gem'i gerekir). Normal kullanım için
üreticiye ihtiyaç yoktur; `.xcodeproj` hazır olarak bulunur.

## 2 Ekim 2026 doğrulaması

- Xcode 27.0 ile `CarMirror / Debug` ARM64 simülatör derlemesi geçti.
- `CarMirror CarPlay / Debug-CarPlay` iPhone derlemesi
  `CODE_SIGNING_ALLOWED=NO` ile geçti. Bu imzalı IPA veya fiziksel cihaz kurulumu değildir.
- 8 çekirdek + 2 medya testi, toplam **10 XCTest**, sıfır hatayla geçti.
- Testin ürettiği H.264 akış tekrar çözüldü; 960 × 540 çıkış, dikey görüntünün
  kenar boşlukları ve durdurma sonrası erişim iptali doğrulandı.
- `CarMirror Prototype` adlı bağımsız iPhone 17 Pro Max / iOS 26.5 simülatörüne
  kuruldu, açıldı ve ana ekranın görüntüsü alındı: `build/simulator-home.png`.
- `CarMirror / Debug` Apple Development sertifikasıyla imzalandı;
  `codesign --verify --deep --strict` kontrolü geçti.
- **CarMirror 0.1.0 (1)** fiziksel **iPhone 16 Pro / iOS 27.0** cihazına kuruldu.
  Açılış komutu başarılı; CarMirror işleminin çalışmaya devam ettiği doğrulandı.
  Telefon kilitli olduğu için fiziksel cihazda arayüzün görünür durumu henüz
  doğrulanamadı; kurulum ve işlem kontrolü arayüz testi yerine geçmez.
- Ana uygulama ve yayın uzantısının provisioning profilleri aynı App Group'u
  ve test telefonunu içeriyor. Cihazdaki uygulama kaydında
  `group.com.alperbicer.carmirror` erişimi de doğrulandı.
- `CarMirror CarPlay / Debug-CarPlay` için otomatik provisioning ile imzalama
  denendi ve başarısız oldu: Xcode, `com.apple.developer.carplay-video`
  yetkisinin bulunamadığını ve profile eklenemediğini bildirdi.
  Telefona kurulan normal sürüm CarPlay Video yetkisi içermiyor.
- Son derlemelerde kaynak kodu uyarısı yok. Xcode'un AppIntents bağımlılığı
  bulunmadığı için metadata çıkarımını atladığını bildiren araç uyarısı var.
- Fiziksel iPhone'da ReplayKit yayını, YouTube/IPTV sesi ve gerçek araçta
  görüntü aktarımı henüz test edilmedi.

Yerel kanıtlar: `build/tests.log`, `build/build-simulator.log`,
`build/build-device-carplay.log`, `build/build-iphone-signed.log`,
`build/build-iphone-carplay-signed.log`, `build/iphone-install.json`,
`build/iphone-launch.json`, `build/iphone-app.json`, `build/iphone-processes.json`.
`build/` geçici çıktılar içindir.

## Apple kaynakları

- [CarPlay Video ve araç desteği](https://developer.apple.com/videos/play/wwdc2026/212/)
- [CarPlay yetkileri](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
- [ReplayKit sistem yayın seçicisi](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview)
- [AVAssetWriter ile HLS bölümleri](https://developer.apple.com/videos/play/wwdc2020/10011/)
- [Korumalı içeriğin yakalanması](https://developer.apple.com/library/archive/qa/qa1970/_index.html)
