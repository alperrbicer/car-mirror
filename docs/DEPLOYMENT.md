# CarMirror: cihaz kurulumu ve App Store komutları

Bu komutlar CarMirror'ın Swift/Xcode projesi içindir. Ana uygulama ve ReplayKit
yayın uzantısı birlikte derlenir. Scan Tools'taki komut düzeni örnek alınmıştır;
CarMirror için Capacitor, CocoaPods veya Android adımı yoktur.

## Başlangıç

macOS, Xcode 27, Xcode Command Line Tools ve Node.js 22.12+ gerekir. Bun yalnızca
komut kısayolları içindir; `bun install` gerekmez. Node komutları Bun olmadan da
çalışır. Xcode'da Apple hesabını ve imzalama sertifikalarını ayarla.

```sh
cd /Users/alperbicer/Documents/projects/private/car-mirror

# Var olan yerel ayarları koruyarak örnek dosyaları oluştur:
test -f Config/Local.xcconfig || cp Config/Local.xcconfig.example Config/Local.xcconfig
test -f .env.deploy || cp .env.deploy.example .env.deploy
```

`Config/Local.xcconfig` içinde `DEVELOPMENT_TEAM = TAKIM_KIMLIGIN` ayarını yap.
Gerekirse `MIRROR_BUNDLE_ID` değerini de bu dosyada değiştir. `.env.deploy`
içindeki `MIRROR_TEAM_ID`, Xcode takım ayarını yalnızca bu komutlar için ezer.
Kabuk ortamındaki değişkenler `.env.deploy` değerlerinden önceliklidir.

Varsayılan kimlikler:

| Bileşen | Kimlik |
| --- | --- |
| Ana uygulama | `com.alperbicer.carmirror` |
| Yayın uzantısı | `com.alperbicer.carmirror.broadcast` |
| Ortak App Group | `group.com.alperbicer.carmirror` |

Apple Developer'da ana uygulama için **CarPlay Audio + CarPlay Video** yetkileri,
iki uygulama kimliği için de aynı App Group gerekir. Apple başvurusunun alınmış
olması yetkilerin provisioning profile'a verildiği anlamına gelmez. Projede
önceden kaydedilen imzalama denemesi bu iki CarPlay yetkisi eksik olduğu için
başarısızdır. Yerel güncel durumu `mobile:doctor` ile kontrol et; komut Apple
portalını sorgulamaz.

Komutlar `CarMirror` scheme'ini ve mevcut `.xcodeproj` dosyasını kullanır.
Proje üreticisini çalıştırmaz, kaynak sürüm/build numarasını veya entitlement
dosyalarını değiştirmez. CarPlay yetkileri eksik bir sürüme otomatik geçiş yoktur.

## Komutlar

| Komut | Yaptığı işlem |
| --- | --- |
| `bun run mobile:doctor` | Xcode, takım, yerel sertifika/profil ve API anahtarı ayarını kontrol eder |
| `bun run mobile:devices` | Eşlenmiş iPhone'ları ve kullanılabilir iPhone simülatörlerini listeler |
| `bun run check` | Script testleri + Swift testleri + imzasız simülatör derlemesi |
| `bun run mobile:ios:prepare` | `check` ile aynı; kurulum yapmaz |
| `bun run mobile:ios:install` | Debug derlemesi, imza/profil kontrolü, iPhone'a kurulum ve açılış |
| `bun run mobile:ios:simulator` | Simülatörde derleme, kurulum ve açılış |
| `bun run mobile:ios:archive` | Testler, yeni build numarası ve imzalı Release arşivi |
| `bun run mobile:ios:export` | Son başarılı arşivi App Store IPA olarak dışarı aktarır |
| `bun run mobile:ios:upload` | Yeni arşiv + IPA doğrulaması + App Store Connect yüklemesi |
| `bun run mobile:ios:testflight` | `upload` ile aynı |
| `bun run test:scripts` | Yalnızca kurulum/yayın araçlarının testleri |

Her komutun `--help` ve **işlem yapmayan** `--dry-run` seçeneği vardır:

```sh
bun run mobile:ios:install --help
bun run mobile:ios:testflight --dry-run
# Bun yoksa (başka bir dizinden de çalışır):
node /Users/alperbicer/Documents/projects/private/car-mirror/scripts/ios.mjs doctor
```

`--dry-run` komut planını gösterir; sertifika, profil veya cihaz hazır olduğu
anlamına gelmez. Dosya yazmaz, build numarası tüketmez, Apple'a bağlanmaz.

## iPhone ve simülatör kurulumu

```sh
bun run mobile:devices
bun run mobile:ios:install --device 'IPHONE_UDID' --allow-provisioning-updates
bun run mobile:ios:simulator --device 'SIMULATOR_UDID'
```

Simülatör kurulumu App Group erişimi için ad hoc imzalanır; Apple profili istemez.
`check` komutunun imzasız derlemesi yalnızca derlenebilirliği doğrular.
Simülatör penceresi Xcode 27'de Device Hub üzerinden açılır; eski Xcode için
Simulator denenir. Pencere açılamazsa `simctl` kurulum/açılış sonucu korunur.

Cihaz adı da kullanılabilir. Birden fazla iPhone eşleşirse komut UDID ister;
rastgele bir cihaz seçmez. Simülatörde tek açık iPhone varsa varsayılan odur.
iPhone'u Xcode ile eşleştir, kilidini aç ve Geliştirici Modu'nu etkinleştir.
Cihazın geliştirme profillerinde kayıtlı olması gerekir; script cihazı Apple
Developer'a otomatik kaydetmez.

`--allow-provisioning-updates`, Xcode'un Apple'daki profilleri oluşturmasına veya
güncellemesine izin verir. Bu seçenek olmadan yerel imzalama kaynakları
kullanılır. CarPlay başvuru/onay adımını tamamlamaz. API anahtarı ayarlıysa onu,
yoksa Xcode'daki Apple hesabını kullanır.

Her derleme ayrı DerivedData dizini kullanır. Kurulumdan önce ana uygulama ve
uzantının bundle ID, sürüm/build, App Group, imza, profil tarihi ve cihaz kaydı
kontrol edilir; ana uygulamada iki CarPlay yetkisi de aranır. Derleme/kurulum
başarısız olursa sonraki adım çalışmaz. Kurulum mevcut uygulamayı silmez.
Açılış komutunun başarısı, görünür ekran veya araçta çalışan görüntü kanıtı değildir.

## Arşiv, IPA ve TestFlight

App Store Connect'te uygulama kaydını aynı bundle ID ile oluştur. Yükleme için
App Store Connect takım API anahtarının gerekli uygulama/yükleme erişimi olmalı.
`.env.deploy` dosyasındaki alanlar:

```dotenv
APP_STORE_CONNECT_KEY_ID=ANAHTAR_ID
APP_STORE_CONNECT_ISSUER_ID=ISSUER_UUID
APP_STORE_CONNECT_PRIVATE_KEY_PATH=/tam/yol/AuthKey_ANAHTAR_ID.p8
```

Anahtar yolu boşsa `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` aranır.
`.env.deploy`, `Config/Local.xcconfig` ve `.p8` dosyaları Git tarafından yok sayılır.

```sh
# Tek komutta yeni arşiv, doğrulanmış IPA ve Apple'a yükleme:
bun run mobile:ios:testflight --allow-provisioning-updates

# Adımları ayrı çalıştırmak için:
bun run mobile:ios:archive --version 0.1.0 --allow-provisioning-updates
bun run mobile:ios:export --allow-provisioning-updates

# Aynı arşivin yüklemesini tekrar denemek için:
bun run mobile:ios:upload --archive '/tam/yol/CarMirror.xcarchive' --allow-provisioning-updates
```

Arşiv sırasında build numarası, kaynak değeri ve `build/deploy/last-build.json`
sayacının büyüğünden bir artırılır. Kaynak dosyalar değişmez; başarısız arşiv
denemeleri numara tüketebilir. Bu sayaç Apple'daki en son build'i sorgulamaz ve
`build/` silinirse sıfırlanır. Başka makineden yükleme yaptıysan veya sayacı
sildiysen App Store Connect'i kontrol ederek `--build 15` gibi daha yüksek bir
numara ver. Ana uygulama ve uzantı aynı sürüm/build ile üretilir; Xcode'un
yükleme sırasında numarayı değiştirmesi kapalıdır.

`export` en son **başarıyla doğrulanmış** arşivi seçer. `--archive` ile açık bir
yol da verebilirsin. Mevcut arşiv kullanılırken `--version`/`--build` verilmez.
IPA dışarı aktarıldıktan sonra dağıtım profilleri ve yetkiler yeniden kontrol
edilir. Yükleme, doğrulanan aynı arşivden Xcode'un `destination=upload` yolu ile
yapılır. Çıktılar ve başarılı işlem kayıtları `build/deploy/` altında saklanır:
`.xcarchive`, `.ipa`, export seçenekleri ve JSON işlem kayıtları.

Başarılı upload sonrasında Apple'ın build'i işlemesini bekle. TestFlight test
grupları, ihracat uyumu soruları, mağaza bilgileri, ekran görüntüleri ve App Review
gönderimi App Store Connect'te tamamlanır. Bu komutlar incelemeye göndermez veya
uygulamayı herkese açık yayımlamaz. Bkz.
[Apple'ın build yükleme belgesi](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Bir adım başarısız olursa

- **CarPlay yetkisi/profili eksik:** Apple onayı ve ilgili App ID yetkilerini
  kontrol et; ardından profilleri yenile. Script yetkiyi kaldırarak devam etmez.
- **Sertifika yok:** Xcode → Settings → Accounts üzerinden doğru takımı ve
  Apple Development/Distribution sertifikalarını ayarla.
- **CoreDevice/cihaz bulunamadı:** Xcode'da Devices and Simulators ekranını aç,
  iPhone bağlantısı, kilidi, eşleşmesi ve Geliştirici Modu'nu kontrol et.
- **Build zaten yüklenmiş:** Yeni arşive daha yüksek `--build` ver. Aynı build'in
  tekrar yüklenmesine Apple karar verir; yerel sayaç bunu doğrulayamaz.
- **API anahtarı veya erişim hatası:** `.env.deploy` alanlarını, anahtar yolunu ve
  App Store Connect rol/uygulama erişimini kontrol et.
