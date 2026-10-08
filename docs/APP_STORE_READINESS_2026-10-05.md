# Mirivo App Store hazırlığı — 5 Ekim 2026

**Henüz incelemeye gönderilmeye hazır değil.** 22 dilin ekran görüntüleri, mağaza metinleri, gizlilik URL'leri ve iki ürünün 44 yerelleştirmesi tamamlandı ve kalıcılığı doğrulandı. 6 Ekim 00:43 sonrası kontrolde kalıcı reklam sözü kaldırılmış build 12 Apple'da Validated, sürüm 1.0'a seçilip kaydedilmiş ve kendi TestFlight grubunda Testing. Güncel iki Pro inceleme görseli yüklendi; sayfa yenilemesi ve görsel kontrolle doğrulandı. Yıllık ürün, abonelik grubu ve ömür boyu ürün aynı inceleme taslağında. Sürümün eklenmesini engelleyen son Apple kontrolünde yalnız App Privacy, içerik hakları ve yaş soruları kaldı. Gerçek ödeme testi ve hesap sahibinin vergi/banka bilgileri de açık. Submit for Review yapılmadı.

## Portalda tamamlanan kayıtlar

| Kayıt | Doğrulanan durum |
| --- | --- |
| Sürüm 1.0 | Build 12 seçildi, kaydedildi ve tam sayfa yenilemesi sonrası doğrulandı; manuel yayınlama |
| Dağıtım adayı | 1.0 (12), Validated, minimum iOS 18.0, iPhone, 22 dil; CarPlay Audio var, Video yok |
| Uygulama ikonu | Media Manager sayfası yenilendikten sonra başlıkta doğru Mirivo logosu göründü. Önceki yer tutucunun kesin sebebi belirlenmedi |
| Public mağaza görselleri | 22 dil × 6 iPhone 6.9 inç görüntü: 132 PNG. Sıra ve aynı dile ait 6.5 inç devralması tam sayfa yenilemesinden sonra doğrulandı |
| Sürüm alanları | 22 dilin açıklama, tanıtım, anahtar kelime, support ve marketing URL alanları kaydedildi ve yeniden okunarak doğrulandı |
| App Information | Mirivo adı ve yerelleştirilmiş alt başlıklar 22 dilde kaydedildi ve sayfa yenilemesinden sonra doğrulandı. Entertainment / Photo & Video kategorileri kaydedildi |
| Ortak alanlar | Telif metni, inceleme notları ve iletişim bilgileri kayıtlı; Mirivo hesabı/giriş gerekmiyor |
| Yıllık / ömür boyu ürün | 22 dil/ürün, toplam 44 ad/açıklama yenilemeyle doğrulandı; Kalıcı reklam sözü kaldırılmış iki güncel fiyatlı inceleme görüntüsü ve notları kayıtlı; yeni görüntüler yenileme ve görsel kontrolle doğrulandı. Ürünler/grup aynı üç öğelik taslakta |
| Abonelik grubu | 22 dilde Mirivo Pro / Mirivo kayıtları yeni sayfa açılışından sonra doğrulandı |
| Ana uygulama fiyatı / erişimi | 175 ülkede ücretsiz; saklanan 175 fiyatın tamamı yenileme sonrası sıfır. Gelecek ülkeler dahil; Mac Apple Silicon ve Apple Vision Pro erişimi kapalı |
| Yıllık satın alma seçenekleri | Bireysel App Store satın alımı; toplu koltuk satın alımı Not Allowed olarak kaydedildi |
| Gizlilik politikası URL'leri | 22 dilde kaydedildi ve yenileme sonrası her dil yeniden seçilerek doğrulandı |
| App Privacy veri beyanı | Yedi türün amaç/bağlantı/tracking cevapları tam taslağa kaydedildi ve yenilemeyle doğrulandı; Publish açık, hesap sahibi incelemesi bekliyor |
| TestFlight | Build 12 kendi Mirivo Internal Testers grubunda Testing; tek testçi hesap sahibi. TR/EN kabul notları kaydedildi ve yenilemeyle doğrulandı. Kurulum ve ödeme kabulü doğrulanmadı |
| Yaş / içerik hakları | Kaydedilmedi. Yaş seçimleri otomatik onay denetiminde açık kullanıcı onayı gerektirdiği için reddedildi |
| DSA | App Information'da Non-trader göründü; ücretli Pro için hesap sahibi yeniden değerlendirmeli |

Bağlantılar:

- [Sürüm 1.0](https://appstoreconnect.apple.com/apps/6818560405/distribution/ios/version/inflight)
- [Apple'daki build 12](https://appstoreconnect.apple.com/teams/31972ed8-cc56-40e5-a97f-ecc06b25ed2a/apps/6818560405/testflight/ios/baed1b1a-7ab6-4241-8dea-f76f3d24e4a8/metadata)
- [Yıllık ürün](https://appstoreconnect.apple.com/apps/6818560405/distribution/subscriptions/6818889933)
- [Ömür boyu ürün](https://appstoreconnect.apple.com/apps/6818560405/distribution/iaps/6818966443)
- [Hesap sahibinin alanları ve ödeme kabul akışı](APP_STORE_OWNER_ACTIONS_2026-10-05.md)

## Mağaza görselleri ve build

`Release/AppStore/screenshots/store-20261005/iphone` içinde 22 dil için altışar düzenlenmemiş gerçek UI görüntüsü var. Tüm setler 1320×2868 RGB. Kaynak, başarılı test vakası ve SHA-256 değerleri `iphone-provenance.json`; canlı yükleme, sıra ve kalıcılık kayıtları `upload-manifest.json` içindedir.

Ortak sıra:

1. `01-iptv.png`: kullanıcının IPTV kaynakları
2. `02-channels.png`: kanallar
3. `03-player.png`: gerçek video oynatımı
4. `04-sharing.png`: ekran ve kişisel medya paylaşımı
5. `05-xtream.png`: Xtream Codes kaynak formu
6. `06-carplay.png`: mevcut CarPlay Audio rehberi

6.9 inç seti Apple'ın kabul ettiği 1320×2868 boyutundadır. 6.9 inç sağlanınca 6.5 inç seti ayrıca zorunlu değildir; küçük ekranlar seti ölçekleyerek devralır. Türkçe sürüm sayfasında 6 Ekim'de yeniden `Using 6.9" Display` ve altı dosyanın doğru sırası görüldü. [Apple ekran görüntüsü boyutları](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Tamamlanan diller: tr, en-US, ar-SA, zh-Hans, zh-Hant, de-DE, es-ES, fr-FR, he, hi, id, it, ja, ko, nl-NL, pl, pt-BR, ru, sv, th, uk, vi. Apple yüklemeleri farklı sırada işlediği için setler yeniden sıralandı; tam sayfa yenilemesinden sonra 22 dilin tamamı yeniden seçilerek doğrulandı. Ülke fiyatı ve mağaza dili ayrı kayıtlardır.

Türkçe/İngilizce çekim koşusu geçti. İlk ek-dil koşusu bütünüyle başarısızdı; yalnız başarılı 12 vaka kullanıldı. Kalan sekiz vaka ayrı koşuda geçti. 14 dilde dokuz oynatıcı/ücretsiz sınır etiketi çevrildi; bu dillerin oyuncu görüntüleri yeniden çekildi ve 14 vaka da geçti. Düzeltmeler dağıtım build 11 içindedir.

Orijinal `Resources/ConnectionProbe.mp4` geçici yerel M3U üzerinden oynatıldı; fixture sunucusu durduruldu. Sağlayıcı şifresi veya üçüncü taraf kanal içeriği kullanılmadı. Build 11 ve güncel build 12'nin Apple Device Family alanı iPhone; derlenmiş `UIDeviceFamily=[1]`. iPad mağaza seti gerekmiyor. Önceki tr/en iPad uyumluluk penceresi çekimleri yalnız referanstır.

Arşiv: `build/deploy/2026-10-05T16-08-13-568Z-archive-f8bfb9/CarMirror.xcarchive`.

IPA: `build/deploy/2026-10-05T16-12-16-929Z-export-70a822/ipa/CarMirror.ipa`.

Yükleme kanıtı: `build/deploy/2026-10-05T16-14-48Z-build11-upload/upload.json`. Apple metadata sayfasında Validated görüldü. GoogleAppMeasurement/GoogleCast dSYM eksikleri engelleyici olmayan uyarı verdi. Pro, RevenueCat public SDK yapılandırması ve Firebase mevcut; ürün HTML'i paketlenmiyor.

**CarPlay Video onayı gelmedi.** Güncel build 12 Audio-only; araçta video değer önerisini karşılamıyor. Video onayı sonrası dağıtım profili yenilenmeli, Video yetkili yeni aday hazırlanmalı ve desteklenen park hâlindeki araçta oynatma doğrulanmalı. Mevcut metin ve görüntüler Audio adayını anlatır. [Apple CarPlay](https://developer.apple.com/carplay/).

## Kalıcı reklam sözü düzeltmesi

5 Ekim'de tüm 22 dilin uygulama kataloglarından gelecek sürümlere yönelik reklam sözü kaldırıldı. Pro ekranında yalnız günlük ücretsiz sınır metni kaldı. Türkçe/İngilizce mağaza tanıtımı kaydedildi ve yeniden okunarak doğrulandı; diğer 20 dilin mevcut ifadeleri gelecek sözü içermiyordu. 132 public mağaza görüntüsü bu ifadeyi içermez, yeniden çekim gerekmez. Dört Pro inceleme görseli yeniden çekildi, test ve görsel kontrol geçti. İki İngilizce görüntü ilgili ürünlere yüklendi ve tam sayfa yenilemesi sonrası yeni Apple asset URL'leri/görünümleri doğrulandı.

Yeni arşiv `build/deploy/2026-10-05T19-55-24-871Z-archive-8ac3a3/CarMirror.xcarchive`; IPA `build/deploy/2026-10-05T20-06-37-124Z-export-346b04/ipa/CarMirror.ipa`; başarılı Apple yükleme kaydı `build/deploy/2026-10-05-build12-upload/upload.json`. Derlenmiş 22 katalogda eski kalıcı söz anahtarlarının olmadığı doğrulandı. 26 gizlilik manifesti build 11 ile aynı. 46 Core testi ve Pro annual/lifetime UI çekim vakası geçti. Dört 1320×2868 düzenlenmemiş görüntü `Release/AppStore/screenshots/pro-plans` içinde; tamamı görsel kontrol edildi. 6 Ekim'de iki portal görüntüsü değiştirildi; ilgili ürünler düzenleme için geçici taslaktan çıkarılıp aynı taslağa geri eklendi. Taslak yine üç ürün/grup öğesi içeriyor. Build 12 Apple'da Validated; sürüm 1.0 seçimi kaydedildi ve yenilemeyle doğrulandı. Build 12 Audio-only; Video onayının yerine geçmez.

## Ödeme hazırlığı

Satış modeli yıllık ve ömür boyu Pro; aynı özellikleri açar. Ücretsiz sınırlar günlük iki saat izleme, bir kaynak ve yayın başına on dakikadır. Pro sınırları kaldırır; desteklenen cihazlarda araç modu ve cihaz içi canlı altyazı sağlar. IPTV içeriği/hesabı, DRM veya CarPlay Video yetkisi sağlamaz.

| Ürün | Model | ABD / Türkiye | Kayıt |
| --- | --- | --- | --- |
| `com.alperbicer.carmirror.pro.yearly` | Yılda bir peşin tahsilat, otomatik yenilenir | $19.99 / ₺399.99 | 175 bölge, yıllık seviye 2 |
| `com.alperbicer.carmirror.pro.lifetime` | Tüketilemeyen tek ödeme | $49.99 / ₺999.99 | 175 bölge |
| Haftalık taslak | Satış dışı | — | 0/175 bölge, seviye 1; silinmedi |

Fiyatlar/kullanılabilirlik 5 Ekim'de canlı portalda doğrulandı; son oturumda tüm fiyat tabloları yeniden açılmadı. Uygulama StoreKit `displayPrice` kullanır. Ömür boyu satın alma yıllık aboneliği otomatik iptal etmez; Apple abonelik yönetiminden ayrıca iptal gerekir. Uygulama/inceleme notları bunu açıklar; site koşulları yerel olarak tamamlandı.

RevenueCat projesi `7d9b6d16`, entitlement `mirivo_pro`, aktif varsayılan offering yalnız `$rc_annual` ve `$rc_lifetime`. 5 Ekim kaydında Apple bağlantıları Valid credentials. Production/sandbox bildirim URL'leri son App Information oturumunda yeniden görüldü. Gerçek bildirim teslimi ve sandbox işlem kaydı doğrulanmadı.

İki ürün için 22 dilde 44 ad/açıklama `product-localizations-20261005.json` içinde; tamamı portalda kaydedildi ve tam sayfa yenilemesi sonrası doğrulandı. Abonelik grubunun 22 dil kaydı da yeni sayfa açılışından sonra doğrulandı. Ana uygulama ücretsiz, yalnız Pro ürünleri ücretlidir. 175 ülkenin saklanan temel fiyatları sıfır olarak doğrulandı; vergi kategorisi App Store Software ve ürünler üst uygulamanın kategorisini kullanır. Test edilmemiş Mac Apple Silicon / Apple Vision Pro dağıtımı kapatılıp yenilemeyle doğrulandı. Yıllık ürünün başlangıçtaki toplu koltuk seçeneği, mevcut bireysel tüketici lisansına uymadığı için Not Allowed / The App Store olarak düzeltildi.

Güncel fiyatlı ödeme UI testi geçti. Yerel StoreKit satın alma/geri yükleme/iade/bitiş testleri iOS 26.5'te SKInternalErrorDomain Code=3 ile başarısız; iOS 27 Device Hub zaman aşımı verdi. **Gerçek Apple sandbox/TestFlight ödeme akışı doğrulanmadı.** Build 12 kendi internal grubuna eklendi ve yenileme sonrası Testing görüldü; tek testçi hesap sahibi. Davetin son 5 Ekim kontrolü Invited; kabul/kurulum sonucu doğrulanmadı. TR/EN What to Test notları kaydedilip yenilemeyle doğrulandı. Fiziksel cihazda daveti kabul edip 1.0 (12) kurduktan sonra satın alma, geri yükleme, yenilenme/bitiş, iade, yeniden kurulum, ReplayKit Pro ve RevenueCat işlem/bildirim kanıtı bekliyor.

## Gizlilik ve site

`privacy-manifests-build-12.json` güncel dağıtım adayındaki 26 manifestin kanıtıdır; manifestler build 11 ile aynı. 6 Ekim'de yedi türün yapılandırması ve Türkçe politika URL'si tekrar görüldü; geçici sayfa yükleme hatası yenilemeyle giderildi. `privacy-inventory.json` envanteri; `privacy-form-draft-20261005.json` yayımlanmamış teknik taslaktır.

Firebase topic modunda; Authentication registry yolu etkin değil. Kullanım Analytics'i açık tercihle etkinleşir, varsayılan kapalıdır. IDFA, IDFV, reklam kişiselleştirme ve custom Analytics user ID kapalıdır. Cast keşif analitiği kapalı olsa da paketlenmiş SDK etiketi başka tanılama işlemelerini açıklar; bunlar hesaba katıldı.

Satın alma geçmişi, Device ID, Product Interaction, Coarse Location, Performance Data, Other Diagnostic Data ve Other Data Types portal taslağına kaydedildi; yedi türün amaç/bağlantı/tracking yapılandırması tamamlandı ve sayfa yenilemesi sonrası doğrulandı. İlk dört tür cihaz/app-instance ilişkisi nedeniyle ihtiyatlı olarak linked Yes; tanılama ve Other Data kurulu SDK beyanlarına göre No. Tüm tracking cevapları No. Publish açık, yayımlanmadı. Rastgele kimlik veya uygulama hesabının olmaması, Apple'ın kimlikle bağlantısız sınıfını tek başına kanıtlamaz. [Apple](https://developer.apple.com/app-store/app-privacy-details/), [Firebase](https://firebase.google.com/docs/ios/app-store-data-collection), [Analytics](https://support.google.com/analytics/answer/10285841), [RevenueCat](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy), [Cast](https://developers.google.com/cast/docs/ios_sender/app_privacy).

Mirivo Firebase projesi / Analytics property 557377354 canlı okundu: Google signals kapalı, Google Ads ve AdMob bağlantıları sıfır, Google Products & Services paylaşımı kapalı. Toplu modelleme, teknik destek ve iş önerisi paylaşımı açık. Genel konum/cihaz verisi ve property reklam kişiselleştirmesi 307 bölgede açık; uygulama reklam consent'i denied ve IDFA/IDFV yok. Ayarlar değiştirilmedi. Analytics Data Processing Terms kabul edilmemiş; uygulanabilirliği hesap sahibi değerlendirmeli ve gerekiyorsa kendisi kabul etmeli. RevenueCat girişi sonrası varsayılan yearly/lifetime teklif, dört anonim RCAnonymousID kaydı ve sıfır ücretli abone/gelir görüldü. Kimlik attribute değeri görülmedi; kaynak kodu custom ID/attribute tanımlamıyor. Entegrasyon kataloğu yapılandırılmış kayıt göstermedi; Firebase/Meta gerekli alanları boş ve Add integration durumunda. Ayarlar değişmedi. Son taslak hesap sahibinin yayın incelemesi için hazır.

Canlı Netlify sitesi reklam sözü düzeltmesiyle 5 Ekim 23:06'da `6ac403313eda88f818df1f24` dağıtımına geçti. Yalnız kalıcı reklam ifadeleri kaldırıldı; önceki 17 dosyanın diğer içeriği korundu. Türkçe/İngilizce sekiz ana sayfa, yardım, koşul ve gizlilik sayfası canlı doğrulandı. Önceki 15:15 ZIP'i `build/netlify-6ac394f8bbe7ffd2ecb07a72-published.zip` olarak korunuyor. **Güncel `Release/mirivo-netlify.zip` farklıdır ve yayımlanmadı:** Cast/Analytics verileri, RevenueCat satın alma analitiği, yıllık peşin tahsilat ve ömür boyunun yıllığı iptal etmemesi eklendi. Son kontroller ve hesap sahibi incelemesinden sonra yayımlanıp canlı içerik doğrulanmalı.

## Kalan işler

Kalan işlemler:

- Tam App Privacy taslağını hesap sahibinin inceleyip Publish etmesi.
- Yaş ve içerik hakları alanlarını hesap sahibinin doğru beyanıyla tamamlamak. Son Add for Review kontrolünün kalan üç engeli gizlilik, içerik hakları ve yaş; temel fiyat engeli giderildi.
- Sandbox/TestFlight ödeme kabulünü kendi fiziksel cihazında tamamlamak. Build 12 internal erişimi hazır, kurulum/işlem sonucu doğrulanmadı.
- Bu engeller kalkınca sürüm 1.0'ı mevcut yıllık/grup/ömür boyu taslağına eklemek. Üç ürün/grup öğesi hazır; uygulama sürümü henüz eklenmedi. [Apple ilk ürün gönderim akışı](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/).
- Onaylanan site metnini yayımlayıp canlı URL içeriklerini doğrulamak.
- CarPlay Video hedefi için Apple onayı, yeni yetkili dağıtım build'i ve desteklenen park hâlindeki araçta kabul.

Hesap sahibine ait: yaş, içerik hakları, DSA, vergi/banka, bağlayıcı anlaşmalar, son gizlilik yayını ve Submit for Review. Business canlı kontrolünde Paid Apps Agreement Pending User Info, U.S. Tax Questionnaire Missing Tax Info ve Bank Accounts boş görüldü; ödeme almak için banka hesabı eklenmesi gerekiyor. Free Apps Agreement Active. Alan açıklamaları `APP_STORE_OWNER_ACTIONS_2026-10-05.md` içindedir. Sorular/onaylar teknik işler sonuna bırakıldı.

Yerel doğrulama: `python3 scripts/verify_release.py` geçti (12 HTML, 22 dil, 269 anahtar, 5.918 çeviri, 0 hata). Build hazırlığında 46 Swift core testi ve dağıtım testleri geçti. Bunlar canlı ödeme, fiziksel araç veya App Review kabulünü kanıtlamaz.

Son dosya kontrolü: `Release/AppStore/preparation-validation-20261005.json`. 132 PNG hash/boyut/RGB, 22 metin alanı sınırları ve 44 ürün yerelleştirmesi doğrulandı. Arşiv ve dağıtım IPA imzası sistem sertifika servisiyle doğrulandı; IPA profili production APNs, get-task-allow=false, Audio=true, Video=false. Sandbox içindeki sertifika aracı erişim hatası sistem servisiyle yapılan salt okunur kontrolde giderildi. `git diff --check` ve `git diff --cached --check` geçti; index değiştirilmedi.
