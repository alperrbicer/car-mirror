# Mirivo: Firebase güncelleme ve bildirim altyapısı

## Hazır olan kod

- `Sources/App/FirebaseServices.swift`: yalnız ana iOS hedefinde Firebase Core, Remote Config, Messaging, Auth, Functions ve App Check. Analytics için reklam kimliği desteklemeyen `FirebaseAnalyticsCore` bağlanır. Veri toplama varsayılan kapalıdır; Ayarlar’daki Kullanım analizi tercihiyle açılır. Yapılandırma dosyası yokken Firebase başlatılmaz.
- `AppUpdateStore`: açılışta gerçek sunucu kontrolü, ön plana dönüşte beş dakikalık kontrol aralığı, engel açıkken/elle yeniden denemede önbelleği aşma. Ağ, bozuk JSON, bilinmeyen şema/sürüm veya yanlış App Store adresi uygulamayı kilitlemez. Geçmiş bir zorunlu güncelleme çevrimdışı açılışta kalıcı engel oluşturmaz.
- `NotificationStore`: kullanıcı tercihi ve iOS izni ayrı takip edilir; başlangıçta izin sorulmaz. APNs tokenı Firebase’e aktarılır. Varsayılan konu modunda FCM aboneliği, isteğe bağlı registry modunda cihaz kaydı eşitlenir. Sunucu yanıtı gelmeden “açık” gösterilmez. Kapatma/izin iptalinde konu aboneliği veya registry kaydı kaldırılır; bağlantı hatası ayrıca gösterilir ve sonraki açılışta denenir.
- `Firebase/functions`: App Check ve anonim Auth doğrulamalı kayıt fonksiyonu, Firestore işlemleriyle token sahipliği ve artan revizyon, izin verilen üç hedefe (`home`, `library`, `settings`) bildirim gönderen yönetici komutu. Medya/URL açtırılmaz.
- Firestore doğrudan istemci okumaları/yazmaları kapalıdır. Token ve kullanıcı anahtarları loglanmaz. Eski token için gelen FCM hatası yeni tokenı silemez.
- Ana uygulama Push Notifications ve App Attest yetkilerini taşır; ReplayKit uzantısı yalnız App Group kullanır. Önizleme derlemesinin entitlement geçersiz kılması yalnız ana uygulamayı etkiler.

## Canlı kurulum durumu — 5 Ekim 2026

- Firebase projesi: [`mirivo`](https://console.firebase.google.com/project/mirivo/overview), Spark (ücretsiz); Blaze açılmadı.
- iOS uygulaması: `com.alperbicer.carmirror`; Firebase App ID `1:1048434391164:ios:d00a9eeff4cd5a59a731f9`; App Store ID `6818560405`.
- Google Analytics konsolda açık, proje oluşturma sırasında Gemini kapalı seçildi. Uygulamada analiz toplama yalnız Kullanım analizi tercihi açıldığında başlar.
- `Config/GoogleService-Info.plist` indirildi, git dışında tutuluyor. Dosya yalnız ana hedefin kaynaklarına eklendi; ReplayKit uzantısına kopyalanmaz. Yeni bir depo kopyasında derlemeden önce bu dosyayı indir. Firebase olmadan yerel derleme istersen dosya yokken `ruby scripts/generate_project.rb --replace` çalıştır; proje üreticisi olmayan dosyanın başvurusunu eklemez ve uygulama Firebase olmadan açılır.
- Remote Config `ios_update_policy` yayımlandı ve tekrar okunarak doğrulandı: `enabled=false`, `minimumVersion=1.0`, `storeURL=""`.
- Cloud Messaging V1 API açık. Firebase’e geliştirme APNs anahtarı `PL5JTXPC2S` ve üretim APNs anahtarı `Z47939ANXF`, Team ID `3T2VY64864` ile yüklendi; iki satır konsolda doğrulandı. Her anahtar yalnız `com.alperbicer.carmirror` konusuna ve kendi ortamına yetkilidir. Özel `.p8` dosyaları repo dışında `~/.private_keys/mirivo-apns/` içinde, klasör `0700` / dosyalar `0600` izinleriyle saklanır.
- Apple Developer’da ana uygulamanın Push Notifications ve App Attest yetkileri açıldı ve yeniden okunarak doğrulandı. Geliştirme profili 5 Ekim 2026’da yenilendi; imzalı derleme, fiziksel iPhone 16 Pro’ya kurulum ve başlatma başarılı. Cihazda bildirim izni, FCM konu aboneliği, kapatma ve yeniden açma kontrol edildi. Yalnız bu cihaza gönderilen tek “Mirivo test bildirimi”, 5 Ekim 2026 14:11 TSİ’de Bildirim Merkezi’nde görüldü. Kişisel Odak açık olduğu için sessiz bildirim grubunda yer aldı.
- Yerel Release arşivi ve App Store dağıtım IPA’sı üretildi. Ana uygulama ve ReplayKit uzantısının imzaları/profilleri doğrulandı; ana uygulama `aps-environment=production` ve App Attest `production` taşıyor. Sürüm `1.0 (10)` 5 Ekim 2026’da App Store Connect’e yüklendi, Apple tarafından onaylandı ve yalnız mevcut `Mirivo External Testers` grubunda `Testing` durumuna geçti. Yeni internal tester eklenmedi. Aynı gün fiziksel iPhone 16 Pro / iOS 27 üzerinde TestFlight’tan `1.0 (10)` kuruldu ve açıldı; bildirim ayarı yeniden açıldığında `Bildirimler açık` durumunu korudu. Kullanıcı onayıyla genel kanala 5 Ekim 2026 15:48’de tek FCM HTTP v1 testi gönderildi; HTTP 200 alındı ve TestFlight sürümünde fiziksel Bildirim Merkezi teslimi görüldü. Kişisel Odak bildirimi sessize aldı. İkinci test ayrıca kullanıcı onayıyla 15:54’te gönderildi. Öncesinde Mirivo ana ekrana getirildi, süreci kapatıldı ve çalışmadığı doğrulandı. Bildirim teslimi görüldü; kullanıcı fiziksel TestFlight cihazında dokunma yönlendirmesinin doğru çalıştığını doğruladı. Toplam iki üretim testi gönderildi.
- Varsayılan `MIRIVO_NOTIFICATION_REGISTRATION_MODE=topic`. Auth/Firestore/Functions kurulmadan ücretsiz genel duyurular kullanılabilir. Cihaza özel kayıt sunucusu kodu hazırdır; canlı ortamda etkinleştirilmedi.

## Ücretsiz genel duyuru kurulumu

1. Apple Developer’da `com.alperbicer.carmirror` için Push Notifications yetkisini aç ve imzalama profillerini yenile. Firebase [Cloud Messaging ayarlarına](https://console.firebase.google.com/project/mirivo/settings/cloudmessaging) APNs `.p8` anahtarı, Key ID ve Team ID bağla. Geliştirme ve üretim ortamlarının ikisini de doğrula; dağıtım imzası `aps-environment=production` olmalı. Özel anahtarları repo’ya veya uygulamaya koyma.
2. Telefonda Ayarlar → Bildirimler’i açıp iOS iznini ver. Uygulama APNs/FCM kaydı sonrası `mirivo_announcements_ios` konusuna abone olur. FCM yanıtı gelmeden “açık” gösterilmez. Ağ kesilirse bekleme sınırlıdır; kapatma bilgisi saklanıp sonraki bağlantıda yeniden denenir. Konudan çıkma Firebase kurulum kimliğini silmez.
3. Firebase Messaging → yeni bildirim kampanyasında hedef olarak bu **konuyu** seç. İlk testte yalnız kendi test cihazını kullan. İsteğe bağlı özel veri `route=home`, `route=library` veya `route=settings` olabilir. Başka hedefler yok sayılır. Uygulama kapalıyken bildirime dokunmayı da doğrula.
4. Konular genel duyurular içindir; özel kullanıcı bilgileri veya erişim sırrı taşımaz. Konu adı yetkilendirme mekanizması değildir. Konu aboneliği ve FCM ücretsizdir; ayrı Functions sunucusu gerekmez. [FCM fiyatlandırması](https://firebase.google.com/pricing), [konu abonelikleri](https://firebase.google.com/docs/cloud-messaging/manage-topic-subscriptions).

İndirilebilir yeni App Store sürümü doğrulanmadan güncelleme zorunluluğunu açma. `MIRIVO_APP_STORE_ID` depoda Mirivo’nun gerçek sayısal ID’siyle ayarlıdır.

## Araç bağlantısında yerel hatırlatma

Ayarlar → Bildirimler → **Araç bağlantısında hatırlat** varsayılan kapalıdır ve Genel duyurular tercihinden bağımsızdır. Kullanıcı açtığında gerekirse iOS bildirim izni istenir. Firebase yapılandırması, FCM aboneliği, konum veya hareket izni gerekmez; araç bağlantısı sunucuya ya da Analytics’e gönderilmez.

`CarPlaySceneDelegate` yeni bir uygulama CarPlay oturumu algıladığında `CarConnectionReminderStore` telefonda tek yerel bildirim ister: **Mirivo araç bağlantısına hazır**. Bildirime dokunmak ana ekranı açar. CarPlay’de bildirim göstermeyi açan bir kategori tanımlanmaz. iOS bildirim izni, Odak ve kullanıcının sistem bildirim tercihleri geçerlidir. [Apple yerel bildirim belgesi](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

Aynı oturumun tekrar çağrıları, ayarı kapatıp açmak ve aynı sahneyle süreç yeniden başlatılması ikinci bildirim üretmez. Oturum işareti zamanlama isteğinden önce kalıcı saklanır; sonucu belirsiz bir hata aynı oturumda yeniden denenmez. Algılanan bağlantı kopması yeni oturuma izin verir. Ayarı mevcut bağlantı sırasında açmak sonraki algılanan oturum için geçerlidir. Kapatma veya kopma, ilgili bekleyen/gösterilmiş yerel bildirimi kaldırır; geciken eski işlemler yeni oturumun bildirimini silemez.

Bu özellik yalnız iOS’un uygulamaya bildirdiği CarPlay sahne bağlantısına dayanır; genel araç/hareket algılaması veya uygulama zorla kapalıyken kesintisiz izleme değildir. Süreç yokken kaçırılan fiziksel kopma yeniden bağlanma olarak varsayılmaz. Gerçek araçla kabul kontrolü: seçenek kapalıyken bildirim gelmemesi; açtıktan sonraki bağlantıda bir bildirim; aynı oturumda tekrar açılışta ek bildirim olmaması; koparıp yeniden bağlayınca yeni bildirim; Genel duyurular kapalıyken yerel bildirime dokunarak ana ekranın açılması. Bu özellik mevcut TestFlight 1.0 (10) paketine dahil değildir.

5 Ekim 2026 yerel doğrulaması: iOS 26.5 simülatöründe 15 `CarConnectionReminderTests`, 13 `AppServicesTests` ve 2 `AppServicesUITests` geçti. Sonuç paketi `build/car-connection-reminder-verified-tests.xcresult`; 22 dilin statik kontrolleri de geçti. Türkçe ayarlar ekranı test görüntüsüyle incelendi. CarPlay olayları servis testlerinde taklit edildi; gerçek araçta yerel bildirim teslimi henüz doğrulanmadı.

## İsteğe bağlı cihaza özel kayıt sunucusu

Bu bölüm yalnız `MIRIVO_NOTIFICATION_REGISTRATION_MODE=registry` kullanılacaksa gerekir. Ücretsiz genel duyuru yolu için gerekli değildir.

1. Firebase Authentication → Sign-in method → Anonymous sağlayıcısını etkinleştir. Kullanıcı giriş ekranı yoktur; anonim kimlik yalnız kurulum kaydını yetkilendirir.
2. Firebase App Check’e iOS uygulamasını App Attest ve desteklenmeyen cihazlar için DeviceCheck ile kaydet. Team ID’yi doğrula. App Attest ortamı `production` olmalı. Simülatör için yalnız yerel Debug yapılandırmasında `MIRIVO_FIREBASE_APPCHECK_DEBUG_ENABLED=YES` kullan ve üretilen debug tokenını konsola kaydet; paylaşma veya git’e ekleme. Release derlemeleri debug sağlayıcısını yok sayar.
3. Firestore’u production rules ile oluştur. Fonksiyonun varsayılan bölgesi `europe-west1`; `MIRIVO_FIREBASE_FUNCTIONS_REGION` ve Functions `FUNCTIONS_REGION` eşleşmeli. Konumu veriyi nerede saklamak istediğine göre seç.
4. Functions dağıtımı ve Firestore TTL için **Blaze faturalandırması gerekir**. Bu projede açılmadı. [Functions koşulları](https://firebase.google.com/docs/functions/get-started), [TTL ücretlendirmesi](https://firebase.google.com/docs/firestore/pricing).
5. Sunucu dağıtılıp doğrulandıktan sonra `Config/Local.xcconfig` içinde `MIRIVO_NOTIFICATION_REGISTRATION_MODE=registry` seç ve fiziksel cihazda kayıt/kapatma işlemlerini test et. Mevcut aboneleri olan bir uygulamada mod geçişini otomatik bir veri taşıma işlemi olarak değerlendirme; eski konu/registry izinlerini temizlemek için ayrı bir geçiş gerekir.

Node.js 22 ve Firebase CLI kullanılır. Spark’ta yalnız force update politikasını yayımlamak için:

```sh
cd Firebase
firebase deploy --project mirivo --only remoteconfig
```

İsteğe bağlı sunucu için faturalandırma ve servisler hazırlandıktan sonra:

```sh
cd Firebase/functions
npm ci
cd ..
firebase deploy --project mirivo --only functions,firestore:rules,firestore:indexes
```

CLI’nin istediği `IOS_FIREBASE_APP_ID=1:1048434391164:ios:d00a9eeff4cd5a59a731f9` değeridir; bundle ID veya proje numarası değildir. `FUNCTIONS_REGION=europe-west1` varsayılandır. Yerel `.env.mirivo` dosyası git dışındadır. Mevcut şablon ve kurallar incelenmeden başka projeye dağıtım yapma.

`notificationInstallations.expiresAt` ve `notificationTokenOwners.expiresAt` TTL alanları dizin dosyasında tanımlıdır. Etkin olduklarını konsolda doğrula. 180 gün yenilenmeyen kayıtlar gönderim kodunda dışlanır; fiziksel TTL silmesi eşzamanlı değildir. Anonim Auth hesabı TTL ile silinmez; ilgili hesabı Firebase Auth yönetimi üzerinden ayrıca silmek gerekir.

## Force update politikası

Remote Config → `ios_update_policy` bir JSON parametresidir. Depodaki başlangıç değeri `enabled=false` bırakır:

```json
{
  "schemaVersion": 1,
  "enabled": false,
  "minimumVersion": "1.0",
  "storeURL": ""
}
```

Örneğin 1.1 tüm desteklenen mağazalarda indirilebiliyorsa `minimumVersion=1.1`, `enabled=true` ve gerçek `https://apps.apple.com/app/idSAYISAL_ID` adresini yayınla. Uygulama bu ID’yi yerel `MIRIVO_APP_STORE_ID` ile eşleştirir. `1.10`, `1.9` sürümünden yenidir; eşit/yeni sürümler engellenmez. Build numarası karşılaştırılmaz. Geri alma için `enabled=false` yayınla. Ekran kapatılamaz; App Store ve yeniden kontrol düğmeleri vardır. Etkin oynatma durdurulur; aynı süreçteki CarPlay oynatma girişleri de engeli kontrol eder.

## Registry modunda bildirim gönderimi

Bu komut yalnız cihaza özel kayıt modundaki izin tablosunu kullanır; varsayılan konu aboneliği için yukarıdaki Firebase Console akışını kullan. Firebase Admin SDK için yetkili Application Default Credentials kullan. Servis hesabı JSON’unu repo içine koyma. Her gönderimden önce alıcının güncel izni yeniden okunur. `--send` olmadan komut yalnız alıcı uygunluğunu kontrol eder, FCM’e göndermez.

```sh
cd Firebase/functions
node send.mjs --project mirivo --file message.example.json --uid ANONYM_AUTH_UID
# İçerik ve alıcı doğrulandıktan sonra gerçek gönderim:
node send.mjs --project mirivo --file message.example.json --uid ANONYM_AUTH_UID --send
# Bütün açık ve güncel kayıtlara gönderim de --all ve açıkça --send gerektirir.
```

Uygulamanın bildirim tercihini gözetmek için bu kayıt tablosunu kullanan göndericiyi kullan; Firebase Console’da bağımsız token listelerine/topluluklara kampanya göndermek aynı izin kontrolünü çalıştırmaz. Kapatma sırasında zaten FCM/APNs’ye kabul edilmiş bir mesaj geri çağrılamaz. `accepted`, FCM kabulünü gösterir; cihazda görünme kanıtı değildir. Komutu yeniden çalıştırmak yeni gönderimdir; kabul edilen mesajlar otomatik tekrar denenmez.

## Doğrulama

Son yerel sonuç: toplam 105 test başarılı — 46 çekirdek Swift testi, 27 dağıtım script testi, gerçek Firestore emülatörüyle 17 backend testi ve 13 iOS servis + 2 arayüz testi. Apple’ın App Attest ortamlarını dizi olarak içeren gerçek geliştirme profili doğrulandı; üretim ortamına izin veren diziler kabul edilirken yalnız geliştirme izni reddedilir. iOS 27 simülatöründe test başlatma takıldı; servis ve arayüz testleri iOS 26.5 simülatöründe geçti. Fiziksel iPhone 16 Pro / iOS 27 üzerinde imzalı kurulum, açılış, bildirim izni, FCM konu aboneliği ve tek gerçek FCM/APNs bildiriminin teslimi doğrulandı. Gönderim HTTP 200 döndü; teslim kanıtı ayrıca telefondaki Bildirim Merkezi’nde görüldü. Genel duyuru gönderilmedi. Yerel üretim IPA’sının ana uygulama ve uzantı dağıtım profilleri de doğrulandı.

Tek cihaz testinde kullanılan geçici FCM adresi sohbete/loga yazılmadı. Mac’teki geçici dosya silindi ve yokluğu doğrulandı; cihazdaki dosyanın Foundation silme çağrısı `YES` döndü. Sonraki bağımsız cihaz dosya listeleme kontrolü CoreDevice hatası nedeniyle tamamlanamadı. Kalıcı APNs özel anahtarları bu test temizliğine dahil değildir.

```sh
node scripts/test_core.mjs --jobs 2 --keep-cache
node --test Tests/Scripts/deployment.test.mjs
node --test Firebase/functions/test/*.test.mjs
cd Firebase
firebase emulators:exec --only firestore --project demo-mirivo 'node --test functions/test/*.test.mjs'
```

Emülatör testi Java 21+ ister. Android Studio kuruluysa onun JBR’si kullanılabilir. Emülatör ortamı yokken Firestore bütünleşme testi açıkça atlanır; saf doğrulama testleri çalışır. iOS test hedefleri `MirivoTests/AppServicesTests` ve `MirivoUITests/AppServicesUITests`.

TestFlight production APNs teslimi ve uygulama kapalıyken bildirime dokunma yönlendirmesi 5 Ekim 2026’da doğrulandı; yönlendirme sonucu kullanıcı cihaz kontrolüne dayanır. Kalan fiziksel kontroller: iOS Ayarları’ndan izni kaldırma, çevrimdışı kapatma ve yeniden bağlantı. İsteğe bağlı registry modu açılırsa App Check kayıtları ayrıca doğrulanır. App Store gizlilik beyanları henüz güncellenmedi. Web gizlilik sayfaları güncellenmiş ve 5 Ekim 2026’da Netlify’de yayımlanmıştır. Uygulama doğrudan bu canlı belgelere link verir; yerel HTML belge kopyası içermez.

Resmî kaynaklar: [Firebase Apple kurulumu](https://firebase.google.com/docs/ios/setup), [FCM/APNs bağlantısı](https://firebase.google.com/docs/cloud-messaging/ios/get-started), [Remote Config](https://firebase.google.com/docs/remote-config/ios/get-started), [App Check zorunluluğu](https://firebase.google.com/docs/app-check/cloud-functions).

## Kullanım analizi

Google Analytics ücretsizdir. Uygulamadaki Kullanım analizi anahtarı varsayılan kapalıdır. Açıldığında yalnız SDK oturum/etkileşim istatistikleri ve sabit `home`, `library`, `settings`, `notifications`, `required_update` ekran adları ölçülür. IDFA destekleyen Analytics ürünü bağlanmaz; IDFV, reklam ağı kaydı ve reklam izinleri kapalıdır. Medya, kaynak başlık/adresleri, aramalar veya Firebase Auth UID analitik olaylarına eklenmez. Kapatma toplama iznini geri alır ve yerel analitik kimliğini sıfırlar. Canlı Analytics raporları fiziksel cihaz ve Firebase DebugView üzerinde ayrıca doğrulanmalıdır. [Ücret bilgisi](https://firebase.google.com/products/analytics/), [veri toplama ayarları](https://firebase.google.com/docs/analytics/ios/configure-data-collection).
