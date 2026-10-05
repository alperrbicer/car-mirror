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

Sürüm 1.0 Türkçe/İngilizce açıklamaları ve inceleme notları yalnız iki planı anlatır. Kullanıcının verdiği inceleme iletişim bilgileri kaydedildi. Kayıt tekrar açılarak iki dil ve iletişim alanları doğrulandı. Yayınlama manuel; incelemeye gönderilmedi.

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

46 Swift core testi ve dağıtım betik testleri geçti. İmzalı Release arşivi ve dağıtım IPA'sı 1.0 (9) olarak oluşturuldu; imza, bundle/App Group, sürüm ve CarPlay Audio dağıtım yetkileri doğrulandı. Arşiv: `build/deploy/2026-10-05T11-28-07-485Z-archive-322bad/CarMirror.xcarchive`; IPA: `build/deploy/2026-10-05T11-30-45-900Z-export-a94545/ipa/CarMirror.ipa`. Apple'a yüklenmedi.

Güncel fiyatlarla Türkçe/İngilizce iki planlı UI testi geçti: varsayılan yıllık, ömür boyu seçimi, haftalık yokluğu, satın alma düğmesi ve $49.99 fiyat kontrolü (`build/pro-current-price-ui-20261005.xcresult`). Düzenlenmemiş dört gerçek ödeme ekranı `Release/AppStore/screenshots/pro-plans` içinde hazır; kaynak ve SHA-256 bilgileri `provenance.json` içindedir. Görüntüler yerel StoreKit USA fiyatını ($19.99 / $49.99) gösterir; Türkçe dil seçimi Türkiye storefront kanıtı değildir. Canlı Apple USA/Türkiye fiyatları ayrı olarak doğrulandı.

Satın alma, geri yükleme, iade, yıllık bitişi ve yıllıktan ömür boyuna geçiş testleri eklendi. iOS 26.5 `SKInternalErrorDomain Code=3` işlem/yapılandırma hatası verdi; satın alma testleri başarısız veya zaman aşımında. iOS 27 test başlatma Device Hub zaman aşımına uğradı. Apple [aynı StoreKitTest semptomunu](https://developer.apple.com/forums/thread/826971) raporluyor; bu, Mirivo'nun satın alma akışının doğrulandığı anlamına gelmez. Xcode IDE Run sırasında Device Hub takıldı; yapılandırma yenilemesinden sonra güncel fiyatlı UI testi geçti. Buna rağmen yıllık bitişi için son tek test tekrar aynı Code=3 ve `notEntitled` hatasıyla başarısız oldu (`build/pro-expiry-recheck-20261005.xcresult`).

Destek sitesi ve `Release/mirivo-netlify.zip` iki planı anlatacak şekilde güncellendi. 22 dil × 264 anahtar, 12 HTML ve ZIP/bağlantı doğrulaması geçti. Güncel ZIP 5 Ekim 2026 15:15 (İstanbul) tarihinde `mirivo-support` Netlify projesine yüklendi; production dağıtımı `6ac394f8bbe7ffd2ecb07a72` “Published” olarak doğrulandı. Canlı 12 HTML sayfasının metin/etiket/bağlantı içeriği ve 2 asset dosyası yüklenen ZIP ile eşleşti. Netlify'nin otomatik pretty URL dönüşümü ve eklediği HTML yorumları karşılaştırmada normalleştirildi. Kanıt: `Release/AppStore/netlify-deployment-20261005.json`.

## Kalan somut işler

- Apple Business: Paid Apps Agreement **Pending User Info**, U.S. Tax Questionnaire **Missing Tax Info**. Vergi/banka ve hukuki kabul kullanıcı tarafından tamamlanmalı; bilgi tahmin edilmedi.
- Hazır güncel fiyatlı gerçek ödeme ekranlarını Apple ürün inceleme alanlarına yükleme.
- Apple sandbox/TestFlight satın alma, geri yükleme, iade, abonelik bitişi, ReplayKit Pro erişimi ve RevenueCat işlem/bildirim kaydını doğrulama.
- Doğrulanmış IPA'yı Apple'a yükleme; App Store build/ürün eşlemesi ve gizlilik beyanını tamamlayıp son inceleme gönderimi. Yerel CLI upload için `.env.deploy` bulunmuyor; RevenueCat'te kayıtlı özel Apple anahtarı yerel dışa aktarılmadı. Xcode hesabıyla yükleme veya mevcut anahtarın sahibi tarafından yerel kurulumu gerekir.

Yerel UI ve derleme sonucu canlı satın alma, cihaz/araç kabulü veya App Review kabulü kanıtı değildir.

## Tek belge kaynağı — 5 Ekim 2026

Netlify’deki 12 HTML sayfası ve asset dosyaları güncel ZIP ile tekrar karşılaştırıldı. Uygulama Ayarlar ve Pro ekranından doğrudan Türkçe/İngilizce Netlify sayfalarına yönlenir. `LegalDocumentView`, yerel WKWebView, dil seçici ve `Resources/Legal` HTML/CSS/logo kopyaları kaldırıldı; site üretimi artık uygulama kaynaklarına belge kopyalamaz. Üçüncü taraf SDK lisansları `Resources/Notices` altında korunur. Belgeleri açmak internet gerektirir; site içindeki dil bağlantısı kullanılabilir. Önceki 1.0 (9) IPA bu bağlantı değişikliğini içermez.

Ayarlar ve Pro ekranındaki toplam 10 Türkçe/İngilizce bağlantının gerçek Safari sayfasına açılması geçti: `build/netlify-links-acceptance-20261005.xcresult` (**TEST SUCCEEDED**, 95.605 saniye, 0 hata). Arapça/İbranice İngilizce siteye yönlendirme testi ayrıca test bazında geçti; birleşik eski koşu başarılı sayılmaz. Derlenen Debug paketinde yerel ürün HTML'i yok; iki SDK lisans bildirimi mevcut. Fiziksel kurulum veya yeni dağıtım IPA'sı bu bağlantı değişikliğinden sonra yapılmadı.
