# Mirivo Pro — 5 Ekim 2026

Mirivo henüz yayımlanmadı ve eski satın alma yok. Satış modeli yalnız yıllık ve ömür boyu Pro; aynı özellikleri açar. Haftalık plan koddan, StoreKit dosyasından ve aktif RevenueCat teklifinden çıkarıldı. Ücretsiz kullanım korunur; her iki sürüm reklamsızdır.

| Erişim | Ücretsiz | Pro |
| --- | --- | --- |
| Günlük izleme | 2 saat, cihaz yerel bütçesi | Sınırsız |
| Kayıtlı kaynak | 1 | Sınırsız |
| Ekran yayını | Oturum başına 10 dakika | Mirivo süre sınırı yok |
| Araç modu ve cihaz içi canlı altyazı | Pro ekranı | Desteklenen cihazlarda açık |

Pro içerik, IPTV hesabı, CarPlay Video yetkisi, araç uyumluluğu veya DRM erişimi sağlamaz.

## Ürünler ve canlı mağaza kaydı

| Ürün | Kimlik | Dönem | ABD | Türkiye |
| --- | --- | --- | --- | --- |
| Yıllık | `com.alperbicer.carmirror.pro.yearly` | Yılda bir tahsil edilir, otomatik yenilenir | $19.99 | ₺399.99 |
| Ömür boyu | `com.alperbicer.carmirror.pro.lifetime` | Tüketilemeyen, tek ödeme | $49.99 | ₺999.99 |

Fiyatlar kullanıcı tarafından onaylandı, App Store Connect'te kaydedildi ve fiyat tabloları tekrar açılarak doğrulandı. İki ürün de 175 ülke/bölgede seçili. Yıllıkta 0 introductory offer; aylık taksitli 12 ay taahhüt planı kurulmadı. Uygulama tutarları StoreKit `displayPrice` üzerinden alır.

Mirivo Apple ID `6818560405`; abonelik grubu `22438082`; yıllık ürün `6818889933`; ömür boyu ürün `6818966443`. Haftalık taslak `6818888654` satıştan kaldırıldı ve **0/175 ülke** erişimi yeniden açılarak doğrulandı. Taslak kalıcı silinmedi. Apple tablosunda yıllık seviye 2, satış dışı haftalık seviye 1 olarak kaldı; seviye sürükleme kaydedilemedi. Tek satıştaki abonelik yıllıktır; eski satın alma taşınması uygulanmaz.

Sürüm 1.0'ın 22 dildeki açıklama, tanıtım, anahtar kelime ve URL alanları kaydedildi ve yeniden okunarak doğrulandı. App Information adı/alt başlıkları ve gizlilik URL'leri de 22 dilde yenileme sonrası doğrulandı. İki ürünün 44 ad/açıklaması ve grubun 22 yerelleştirmesi tamamlandı; kalıcılık kontrolü geçti. Kullanıcının verdiği inceleme iletişim bilgileri ve güncel notlar kayıtlı. Yayınlama manuel; incelemeye gönderilmedi.

Ana uygulama 175 ülkede ücretsiz; kaydedilmiş 175 fiyat yenileme sonrası sıfır. Gelecek bölgeler dahil, Mac Apple Silicon / Apple Vision Pro erişimi kapalı. Vergi kategorisi App Store Software, ürünler üst uygulamayı kullanır. Yıllık ürün bireysel The App Store satın alımı; çoklu koltuk Not Allowed olarak düzeltildi.

## Daelix'ten ayrım ve RevenueCat

[Mirivo RevenueCat projesi](https://app.revenuecat.com/projects/7d9b6d16/overview) `7d9b6d16`; App Store uygulaması `app8e29ebec6d`, bundle `com.alperbicer.carmirror`. Mirivo'ya ait public Apple SDK anahtarı git dışındaki `Config/Local.xcconfig` içindedir. Daelix'in projesi, ürünleri ve SDK anahtarı değiştirilmedi.

Mirivo `mirivo_pro` entitlement (`entl3e0b1e3182`) yalnız gerçek yıllık ve ömür boyu Apple ürünlerine bağlı. Varsayılan aktif offering `mirivo_pro` (`ofrng5cc5d706fb`): `$rc_annual` ve `$rc_lifetime`. Test Store ürünleri entitlement'tan ayrıldı; eski üç paketli test offering'i pasif. Aktif offering listesi ve varsayılan durumu tekrar doğrulandı.

Apple bağlantısında RevenueCat'te zaten saklı olan aynı geliştirici hesabının anahtarları kullanıldı. Her iki bağlantı “Valid credentials”. Bu anahtarlar Apple geliştirici hesabı kapsamındadır; yeni anahtar üretmek onları uygulama kapsamına daraltmaz. RevenueCat [aynı Apple hesabındaki uygulamalarda aynı IAP anahtarını destekler](https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration). Satın alma erişimi ayrı proje, ürün kimlikleri ve uygulamaya özel SDK anahtarıyla ayrıdır. Gizli anahtar uygulamaya konulmaz.

App Store Connect production ve sandbox sunucu bildirim URL'leri Mirivo RevenueCat uygulamasına ait aynı yönlendirmeyle kaydedilmiş olarak doğrulandı. Bildirim teslimi/sandbox işlem kaydı henüz doğrulanmadı.

## Kod davranışı

StoreKit 2 doğrulanmış `Transaction.currentEntitlements` erişimi belirler. İade, abonelik bitişi ve yükseltme yerel erişim hesabında işlenir. ReplayKit uzantısı kendi StoreKit kontrolünü yapar; RevenueCat SDK'sı uzantıya eklenmez. Bekleyen veya doğrulanamayan işlem Pro açmaz. Ön plana dönüşte erişim yenilenir.

Yıllık plan varsayılan seçilir. Plan fiyatı ve yenilenme biçimi görünür. Ömür boyu sahibi yeniden satın alamaz; yıllık sahibi ömür boyuna geçebilir. Ekran, ömür boyu satın almanın mevcut yıllık aboneliği otomatik iptal etmediğini açıklar. Geri yükleme ve Apple abonelik yönetimi erişilebilir.

RevenueCat 5.x ana uygulamada `.myApp` / StoreKit 2 modunda işlemleri gözler. StoreKit satın alma/geri yükleme ve işlem güncellemelerinden sonra senkronize edilir. Erişim RevenueCat ağ isteğine bağlı değildir.

## Doğrulama ve dağıtım

46 Swift core testi ve dağıtım betik testleri geçti. Güncel imzalı Release arşivi ve IPA **1.0 (12)**; CarPlay Audio yetkili, Video kapalı, iPhone-only. Arşiv: `build/deploy/2026-10-05T19-55-24-871Z-archive-8ac3a3/CarMirror.xcarchive`; IPA: `build/deploy/2026-10-05T20-06-37-124Z-export-346b04/ipa/CarMirror.ipa`. Apple yüklemesi başarılı; metadata sayfasında Validated, minimum iOS 18.0 ve 22 dil görüldü. Sürüm 1.0'a kaydedilmiş seçimi tam sayfa yenileme sonrası doğrulandı. Kendi internal TestFlight grubunda Testing; tek testçi hesap sahibi, cihaz kurulumu/ödeme kabulü açık. Davetin son 5 Ekim kontrolü Invited. Netlify bağlantıları, Pro, RevenueCat public SDK yapılandırması ve Firebase mevcut; ürün HTML'i paketlenmez. GoogleAppMeasurement/GoogleCast dSYM eksikleri engelleyici olmayan yükleme uyarılarıdır.

Güncel fiyatlarla Türkçe/İngilizce iki planlı UI testi geçti: varsayılan yıllık, ömür boyu seçimi, haftalık yokluğu, satın alma düğmesi ve $49.99 fiyat kontrolü (`build/pro-current-price-ui-20261005.xcresult`). Düzenlenmemiş dört gerçek ödeme ekranı `Release/AppStore/screenshots/pro-plans` içinde hazır; kaynak ve SHA-256 bilgileri `provenance.json` içindedir. Görüntüler yerel StoreKit USA fiyatını ($19.99 / $49.99) gösterir; Türkçe dil seçimi Türkiye storefront kanıtı değildir. Canlı Apple USA/Türkiye fiyatları ayrı olarak doğrulandı.

Satın alma, geri yükleme, iade, yıllık bitişi ve yıllıktan ömür boyuna geçiş testleri eklendi. iOS 26.5 `SKInternalErrorDomain Code=3` işlem/yapılandırma hatası verdi; satın alma testleri başarısız veya zaman aşımında. iOS 27 test başlatma Device Hub zaman aşımına uğradı. Apple [aynı StoreKitTest semptomunu](https://developer.apple.com/forums/thread/826971) raporluyor; bu, Mirivo'nun satın alma akışının doğrulandığı anlamına gelmez. Xcode IDE Run sırasında Device Hub takıldı; yapılandırma yenilemesinden sonra güncel fiyatlı UI testi geçti. Buna rağmen yıllık bitişi için son tek test tekrar aynı Code=3 ve `notEntitled` hatasıyla başarısız oldu (`build/pro-expiry-recheck-20261005.xcresult`).

Destek sitesinin iki planı anlatan 5 Ekim 15:15 (İstanbul) dağıtımı `6ac394f8bbe7ffd2ecb07a72` Published olarak doğrulandı; o sırada 12 HTML/2 asset içerikleri eşleşti. Bu dağıtımın ZIP'i `build/netlify-6ac394f8bbe7ffd2ecb07a72-published.zip` olarak korundu. Kanıt: `Release/AppStore/netlify-deployment-20261005.json`. **Güncel `Release/mirivo-netlify.zip` henüz yayımlanmadı:** Cast/Analytics verileri ve RevenueCat satın alma analitiği, yıllık peşin tahsilat ve ömür boyunun mevcut yıllığı iptal etmemesi eklendi. Yerel doğrulama geçti: 12 HTML, 22 dil × 269 anahtar, 5.918 çeviri, 0 hata. Son gizlilik incelemesi ve hesap sahibi onayı sonrası yayın/canlı doğrulama bekliyor.

## Kalan somut işler

- Apple Business: Paid Apps Agreement **Pending User Info**, U.S. Tax Questionnaire **Missing Tax Info**, Bank Accounts boş. Vergi/banka ve hukuki kabul kullanıcı tarafından tamamlanmalı; bilgi tahmin edilmedi.
- Güncel fiyatlı gerçek ödeme ekranları ve ürün inceleme notları kayıtlı. Yıllık, abonelik grubu ve ömür boyu ürün mevcut üç öğelik inceleme taslağında hazır; gönderilmediler.
- Apple sandbox/TestFlight satın alma, geri yükleme, iade, abonelik bitişi, ReplayKit Pro erişimi ve RevenueCat işlem/bildirim kaydını doğrulama.
- RevenueCat entegrasyon/kimlik ve Analytics paylaşım/signals/Ads kontrolleri tamamlandı. Yedi türün tüm amaç/bağlantı/tracking cevapları portal taslağında kayıtlı ve yenilemeyle doğrulandı; Publish açık, hesap sahibi incelemesi/yayını yapılmadı. Data Processing Terms kabul edilmemiş, uygulanabilirliği hesap sahibi değerlendirmeli.
- Yaş, içerik hakları ve DSA beyanları hesap sahibine ait; yaş seçimleri otomatik onay denetiminde açık kullanıcı onayı gerektiği için reddedildi.
- App Privacy, Content Rights ve Age Ratings tamamlanınca sürüm 1.0 mevcut üç öğelik taslağa eklenmeli. Son Submit for Review kullanıcıya bırakıldı. Özel Apple anahtarı yerel dışa aktarılmadı.

Yerel UI ve derleme sonucu canlı satın alma, cihaz/araç kabulü veya App Review kabulü kanıtı değildir.

## Tek belge kaynağı — 5 Ekim 2026

Netlify’deki 12 HTML sayfası ve asset dosyaları 15:15 dağıtımının ZIP'iyle karşılaştırılmıştı; hazırlanan sonraki değişiklikler henüz yayında değil. Uygulama Ayarlar ve Pro ekranından doğrudan Türkçe/İngilizce Netlify sayfalarına yönlenir. `LegalDocumentView`, yerel WKWebView, dil seçici ve `Resources/Legal` HTML/CSS/logo kopyaları kaldırıldı; site üretimi artık uygulama kaynaklarına belge kopyalamaz. Üçüncü taraf SDK lisansları `Resources/Notices` altında korunur. Belgeleri açmak internet gerektirir; site içindeki dil bağlantısı kullanılabilir. Önceki 1.0 (9) IPA bu bağlantı değişikliğini içermez.

Ayarlar ve Pro ekranındaki toplam 10 Türkçe/İngilizce bağlantının gerçek Safari sayfasına açılması geçti: `build/netlify-links-acceptance-20261005.xcresult` (**TEST SUCCEEDED**, 95.605 saniye, 0 hata). Arapça/İbranice İngilizce siteye yönlendirme testi ayrıca test bazında geçti; birleşik eski koşu başarılı sayılmaz. Güncel 1.0 (12) dağıtım paketinde yerel ürün HTML'i yok; iki SDK lisans bildirimi mevcut. Bu adayın fiziksel araç kabulü ayrıca doğrulanmalıdır.

5 Ekim mağaza çekimi: 22 dil için altışar iPhone görüntüsü (132 PNG) `Release/AppStore/screenshots/store-20261005` içinde hazır ve App Store Connect'e yüklendi. Her dilde aynı altı dosya sırası ve 6.5 inç alanının aynı dilin 6.9 inç setini devralması tam sayfa yenilemesinden sonra doğrulandı. Build 11 iPhone-only; iPad seti gerekmiyor. 14 dilin dokuz oyuncu/ücretsiz sınır etiketi çevrildi, yeniden çekilen 14 oyuncu vakası geçti ve kaynak düzeltmeleri Apple'da Validated olan build 11'e dahil edildi. Başlıkta doğru Mirivo logosu görüldü. Ayrıntılı durum `docs/APP_STORE_READINESS_2026-10-05.md`, hesap sahibinin alanları `docs/APP_STORE_OWNER_ACTIONS_2026-10-05.md` içindedir.

5 Ekim akşamı: Gelecek sürümlerde hiçbir zaman reklam olmayacağı sözü 22 dilin uygulama kataloğundan kaldırıldı. Türkçe/İngilizce mağaza tanıtımı kaydedilip doğrulandı; destek sitesinin ad-only değişikliği `6ac403313eda88f818df1f24` dağıtımında yayında. Yeni 1.0 (12) arşivi ve IPA Apple'a yüklendi. 6 Ekim kontrolünde Validated, sürüm 1.0'a kaydedilmiş ve kendi internal grubunda Testing. İki güncel Pro inceleme görseli yüklenip yenileme/görsel kontrolle doğrulandı; ürünler aynı üç öğelik taslakta. TR/EN TestFlight kabul notları kayıtlı. Kanıt `Release/AppStore/portal-completion-20261006.json`. RevenueCat teknik kontrolü tamamlandı ve yedi App Privacy türünün tüm cevapları taslağa kaydedilip yenilemeyle doğrulandı; Publish açık, son yayın hesap sahibine ait. Güncel ayrıntılar readiness/owner belgelerinde.
