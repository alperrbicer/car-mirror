# Mirivo — hesap sahibinin alanları ve son kontroller

5 Ekim 2026: 22 dilde 132 public mağaza görüntüsü aynı sırada, tüm metin/URL alanları ve iki ürünün 44 yerelleştirmesi kalıcı olarak doğrulandı. Logo görünür. 6 Ekim'de build 12 Validated; sürüm 1.0 seçimi ve kendi TestFlight grubundaki Testing durumu yenileme sonrası doğrulandı. İki güncel Pro inceleme görseli kayıtlı. Ana uygulama 175 ülkede ücretsiz. Yıllık ürün, abonelik grubu ve ömür boyu ürün aynı inceleme taslağında. Bu belge gereken alanları somutlaştırır; hukuki beyan veya son gönderim onayı değildir.

## Teknik hazırlık tamamlanan adımlar

RevenueCat girişi tamamlandı; Mirivo projesinin teklifi, anonim kimlikleri ve entegrasyon ekranları incelendi. Yeni reklam metni uygulamanın 22 dilinde kaldırıldı ve 1.0 (12) arşivi Apple'a yüklendi. Destek sitesindeki aynı değişiklik 5 Ekim 23:06'da yayımlandı.

App Store Connect erişimi yenilendi. Build 12'nin Validated bilgisi, sürüm 1.0 seçimi, iki yeni Pro görseli ve kendi internal TestFlight Testing kaydı tamamlandı. Türkçe/İngilizce test notları kaydedilip yenilemeyle doğrulandı. Kanıt: `Release/AppStore/portal-completion-20261006.json`.

Aşağıdaki yaş/içerik hakları ve Business alanlarını kendi gerçek bilgilerinle tamamla. Son gizlilik yayını, bekleyen site gizlilik/koşul metinleri, cihazdaki ödeme kabulü ve Submit for Review hesap sahibine ait.

## Yaş derecesi

[Mirivo App Store Connect](https://appstoreconnect.apple.com/apps/6818560405) → App Information → Age Ratings → Set Up/Edit.

Mevcut davranışa göre ilk özellik soruları için öneriler aşağıda. Portalda seçilmedi; hesap sahibi incelemesi gerekiyor.

| Alan | Taslak cevap | Uygulamadaki dayanak |
| --- | --- | --- |
| Parental Controls | No | Ebeveyn PIN'i, içerik filtresi/çocuk yönetimi yok; ücretsiz kota ebeveyn kontrolü değil |
| Age Assurance | No | Yaş doğrulama veya Declared Age Range kullanımı yok |
| Unrestricted Web Access | No | Kaynak URL'leri medya/playlist içindir; uygulama içi serbest tarayıcı yok; belgeler Safari'de açılır |
| User-Generated Content | No önerisi; kapsam onayı gerekir | Kaynaklar kişisel; Mirivo kullanıcı içeriğini genel kitleye dağıtan platform sağlamaz |
| Social Media | No | Sosyal akış, herkese açık profil, beğeni/yorum veya sosyal keşif yok |
| Social Media Disabled for Users Under 13 | No / uygulanmıyor | Sosyal medya veya yaşa göre sosyal medya kısıtı yok |
| Messaging and Chat | No | Kullanıcılar arası sohbet/mesaj yok |
| Advertising | No | Reklam SDK'sı veya ücretli reklam gösterimi yok |

Olgun temalar, sağlık/tıbbi bilgi, cinsellik/çıplaklık ve şiddet için Mirivo arayüzünde/orijinal test içeriğinde ilgili öğeler görülmedi. Kullanıcı kendi IPTV/video kaynağını ekleyebildiğinden tüm oynatılabilir içerik için otomatik None beyanı verilmedi. Hesap sahibi hedef yaşı ve izin verilen içerik kapsamını değerlendirmeli; gerekirse Apple'ın hesapladığı dereceden yüksek yaş geçersiz kılması kullanılmalı. Rastgele 4+ seçilmemeli.

Mirivo içinde kumar, simülasyon, yarışma veya loot box yok; şans temelli özellikler için No/None önerisi var. IPTV içeriğinin kapsamı önceki gruplarla birlikte değerlendirilmeli. Portalın hesapladığı bölgesel dereceler son adımda görülüp kaydedilmeli. [Apple yaş alanlarının tanımları](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).

Otomatik onay denetimi ilk No seçimlerini şu nedenle reddetti: “This makes compliance-sensitive age-rating declarations without explicit user confirmation”. Form iptal edildi; cevaplar kaydedilmedi. Taslağın uygulanması açık kullanıcı onayı gerektiriyor.

## Üçüncü taraf içerik hakları

App Information → Content Rights → Set Up/Edit. Canlı Apple formu üçüncü taraf içerik için gerekli hakların/hukuki iznin bulunduğunu beyan etmeyi istiyor.

Mirivo kendi IPTV kataloğunu/hesabını satmıyor; kullanıcı kendi M3U, sunucu ve Xtream bilgilerini ekliyor. Bu teknik davranış “gerekli haklara sahibim” beyanını kendiliğinden doğrulamaz. Hesap sahibi modelin hak/izin dayanağını değerlendirmeli ve doğru seçeneği onaylamalı. Üçüncü taraf içeriğe erişim yokmuş gibi No seçilmedi. İnceleme demosunda yalnız orijinal Mirivo test videosu kullanılmalı.

## Ödeme sözleşmesi, vergi ve banka

[App Store Connect](https://appstoreconnect.apple.com/) → Business → Agreements → Paid Apps. Son canlı kontrol: **Pending User Info**; U.S. Tax Questionnaire **Missing Tax Info**; **Bank Accounts boş** ve ödeme almak için banka hesabı ekleme uyarısı var. Free Apps Agreement Active.

Hesap sahibi gerçek bilgileri portalda girmeli:

- Vergi formunda hesap türü, vergi ikameti, yasal ad/adres, gerçek faydalanıcı ve istenen vergi numaraları. ABD vergi statüsü, form türü, anlaşma indirimi veya vergi oranı kullanıcı adına varsayılmamalı. Vergi kimliği bu belgeye yazılmamalı.
- Bank Accounts → Add Bank Account: yasal hesap sahibi, banka ülkesi/para birimi ve bankanın sağladığı IBAN/SWIFT/routing bilgileri; portalın doğrulama koşullarını karşılamalı. Banka/vergi kimliklerini sohbete veya bu belgeye yazma; doğrudan Apple'ın formuna gir.
- Yeni Paid Apps şartları varsa son Accept/Agree hesap sahibine ait. Bilgiler tamamlandıktan sonra etkin anlaşma durumunu tekrar doğrulayacağız.

[Apple anlaşma rehberi](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/) ücretli uygulama/IAP için hesap sahibinin Paid Apps anlaşmasını kabul etmesini gerektirir. Bu alanlar gerçek ödeme testinin yerine geçmez.

## DSA ticari durum

App Information'da mevcut beyan **Non-trader**. Ücretli Pro/IAP hedefiyle yeniden değerlendirilmeli. Apple IAP gelirini faktörlerden biri sayıyor; seçim otomatik değiştirilmedi. Trader beyanı gerekiyorsa istenen doğrulanabilir iletişim/adres bilgilerini hesap sahibi sağlamalı. [Apple DSA açıklaması](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

## Gizlilik yayını

Teknik taslak `Release/AppStore/privacy-form-draft-20261005.json`. Build 12'nin 26 manifesti build 11 ile aynı. [App Privacy](https://appstoreconnect.apple.com/apps/6818560405/distribution/privacy) bölümünde yedi türün amaç, kimlik bağlantısı ve tracking cevapları kaydedildi ve tam sayfa yenilemesi sonrası doğrulandı. Publish açık, henüz yayımlanmadı.

| Veri | Amaç | Kimlik bağlantısı taslağı | Tracking |
| --- | --- | --- | --- |
| Device ID | App Functionality, Analytics | Yes | No |
| Purchase History | App Functionality, Analytics | Yes | No |
| Product Interaction | Analytics | Yes | No |
| Coarse Location | App Functionality, Analytics | Yes | No |
| Performance Data | App Functionality, Analytics | No | No |
| Other Diagnostic Data | App Functionality, Analytics | No | No |
| Other Data Types | Analytics | No | No |

Analytics olayları uygulama örneği kimliğiyle ilişkilendirilebildiğinden ilk dört app-level cevapta cihaz bağlantısını ihtiyatlı şekilde dahil ettim. RevenueCat'in tek başına anonim satın alma için verdiği No önerisi, Mirivo'nun isteğe bağlı Analytics satın alma olaylarını otomatik olarak kapsamıyor. Bu, ad/e-posta toplandığı veya reklam takibi yapıldığı anlamına gelmez. Tanılama ve Other Data bağlantısı kurulu SDK beyanlarına göre No. Manifestler isteğe bağlı SDK özelliklerini de içerir; bu nedenle tek manifest satırı tüm uygulamanın son beyanı sayılmadı. Hesap sahibi bu son taslağı okuyup doğru bulduğunda Publish adımını tamamlamalı.

Google Analytics'te Google signals kapalı, Google Ads/AdMob bağlantıları sıfır, Google Products & Services paylaşımı kapalı olarak doğrulandı. Toplu modelleme, teknik destek ve iş önerisi paylaşımı açık. Konum/cihaz toplama ve property reklam kişiselleştirmesi açık; uygulama ad consent'i denied. RevenueCat'te dört RCAnonymousID kaydı ve sıfır ücretli abone/gelir görüldü. İncelenen profilde kimlik/iletişim/reklam identifier attribute değerleri görülmedi; uygulama kaynak kodu da custom ID/attribute tanımlamıyor. Entegrasyon kataloğunda yapılandırılmış kayıt gösterilmedi; Firebase ve Meta şablonlarında gerekli alanlar boş, Add integration durumu görüldü. Ayarlar değiştirilmedi.

Analytics → Admin → Account settings → Account details bölümündeki **Data Processing Terms kabul edilmemiş**. Kendi veri işleme kapsamın için uygulanıp uygulanmadığını değerlendir; gerekiyorsa metni okuyup kendin kabul et. Ben bağlayıcı kabul yapmadım.

Gizlilik/koşul önizlemeleri `Web/tr/privacy.html`, `Web/tr/terms.html`; İngilizceleri `Web/en/` altında. `Release/mirivo-netlify.zip` içindeki Cast tanılaması, Analytics genel konumu/satın alma olayları ve yıllık/ömür boyu ödeme açıklaması henüz yayımlanmadı; son beyan/metin onayı bekliyor. Kullanıcının açık reklam sözü kaldırma talebi ayrı paketle yayına alındı; bu dağıtımda önceki gizlilik/ödeme metinleri korunmuştur.

## Fiziksel TestFlight ödeme kabulü

Şu an seçili build **1.0 (12)** [Mirivo Internal Testers grubuna](https://appstoreconnect.apple.com/teams/31972ed8-cc56-40e5-a97f-ecc06b25ed2a/apps/6818560405/testflight/groups/da4b1168-5aa5-4ea7-8712-04e991e67cc3/builds) eklendi; canlı durum Testing. Tek testçi kendi hesap sahibi hesabın; davetin son 5 Ekim kontrolü Invited. Daveti kendi hesabınla kabul et. Reklam metni düzeltmeli **1.0 (12)** internal grupta hazır; iPhone'a onu kur; eski build 7/10/11 ile sonucu karıştırma. Davet kabulü ve cihaz kurulumu henüz doğrulanmadı.

TestFlight IAP sandbox kullanır; uygulamanın TestFlight'tan kurulduğu ve satın alma sayfasının test ortamı olduğu doğrulanmalı. Gerçek ücretli mağaza satın alımı yapılmamalı. [Apple TestFlight ödeme testi](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/), [Apple sandbox rehberi](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).

| Senaryo | Beklenen sonuç ve kanıt |
| --- | --- |
| Başlangıç | Pro yokken 2 saat/gün, 1 kaynak, yayın başına 10 dakika; yıllık/ömür boyu StoreKit fiyatları yüklenir |
| Yıllık satın alma | Doğrulanmış işlem sonrası Pro; doğru plan/dönem. Zaman, build ve storefront kaydedilir |
| Restore / yeniden kurulum | Aynı test satın alma hesabında doğru erişim; bekleyen/başarısız işlem Pro açmaz |
| Yenilenme / bitiş | Sandbox yenilenme ve sona erme sonrasında doğru erişim; auto-renew kapatmak mevcut dönemi bitirmez |
| İade / revocation | Sandbox'ın sağladığı senaryoda erişim yeniden hesaplanır; gerçek müşteri iadesi yapılmaz |
| Ömür boyu | Tek ödemeyle Pro; geri yükleme/yeniden kurulum sonrası sürer |
| Yıllıktan ömür boyuna | Pro sürer; yıllığın Apple yönetiminden ayrıca iptali gerektiği açıklanır |
| ReplayKit | Ana uygulama ve yayın uzantısı aynı doğrulanmış Pro erişimini uygular |
| RevenueCat | Doğru Mirivo projesinde işlem, entitlement ve Apple bildirimi görünür; teslim kanıtı ayrı kaydedilir |

Yerel fiyatlı UI geçti; satın alma/geri yükleme/iade/bitiş Code=3 ile başarısız. Tablo tamamlanmış test sonucu değildir.

## CarPlay Video ve son gönderim

Video onayı gelmediği kullanıcı tarafından doğrulandı. Build 12 Audio-only. Ana değer önerisi CarPlay Video için onay, Video yetkili profil/build ve desteklenen park hâlindeki gerçek araç kabulü gerekir. Yeniden onay durumu sorulmayacak.

Yıllık ürün, abonelik grubu ve ömür boyu ürün aynı mevcut taslakta **Items Ready to Submit (3)** olarak doğrulandı. Taslakta Submit for Review kapalı; uygulama sürümü eklenmeli. Sürüm 1.0'ın son Add for Review kontrolünde kalan üç zorunlu alan **App Privacy**, **Content Rights**, **Age Ratings**; temel fiyat hatası giderildi.

Bu alanlar ve cihazdaki ödeme kabulü tamamlanınca sürüm 1.0 mevcut üç öğelik taslağa eklenecek. Finalde platform iOS, reklam metni düzeltmeli build 12 veya Video onayı sonrası yeni yetkili aday ve iki satış ürünü birlikte kontrol edilmeli. Satış dışı haftalık taslak gönderilecek ürün değil. Son Submit for Review hesap sahibine bırakılır; manuel yayınlama korunur. CarPlay Video ana hedefi için mevcut Audio-only aday yeterli değildir; Video onayı gelmeden Video özelliği varmış gibi gönderim/metin yapılmamalı.
