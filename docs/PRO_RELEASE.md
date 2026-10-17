> 17 Ekim 2026 canlı güncellemesi: kullanıcı onayıyla haftalık/yıllık fiyatlar, 3/7 günlük denemeler, 175 bölge ve ortak Pro seviyesi App Store Connect’te kaydedildi; RevenueCat varsayılan teklifi yıllık+haftalık olarak güncellendi. Ömür boyu yeni satış kapalı, eski haklar korunuyor. Haftalık ve yıllık inceleme görselleri kullanıcı onayıyla yüklendi ve sayfa yenilenerek doğrulandı; hesap/binary kabulü aşağıdaki açık işlerdir.

## 17 Ekim mağaza metinleri ve yeni inceleme görselleri

Uygulamanın 22 dildeki açıklamaları App Store Connect'e kaydedildi ve yeni sekmeden her dil tekrar açılarak **22/22** eşleşme doğrulandı. Haftalık ürünün 22 dil kaydı yeniden okundu; yıllık ürünün 22 dilde adı/açıklaması aynı dönemsel erişim biçimine geçirildi ve tam sayfa yenilemesinden sonra doğrulandı (**44/44 ürün tanımı**). Güncel dosya `Release/AppStore/subscription-model-20261017.json`; önceki 5 Ekim ürün kayıtları tarihseldir. Uygulama ve ürün inceleme notları yeni üyelik modelini, deneme uygunluğunu, geri yüklemeyi, içerik haklarını ve park halinde CarPlay koşulunu açıklar.

Güncel kaynaklardan iOS 26.5 simülatöründe `StoreKitIntegrationTests/testDisabledSalesCannotStartPurchase` ve `ProductUITests/testWeeklyAnnualSelectionAndCompactBenefits` başarılı oldu. UI koşusu Türkçe, İngilizce ve büyük erişilebilirlik yazılı Arapçada yıllık/haftalık seçimi ve $29.99/$2.99 tutarlarını doğruladı. Bu koşudan alınan değiştirilmemiş altı ekran görüntüsü `Release/AppStore/screenshots/subscriptions-20261017/` altında, kaynak test ve SHA-256 bilgileri `provenance.json` içinde hazır. Sonuç paketi `build/store-metadata-20261017/paywall.xcresult`. Görseller yerel Xcode StoreKit ortamını gösterir; canlı Apple/TestFlight ödeme kanıtı değildir. Kullanıcının açık onayıyla `weekly-en.png` haftalık, `yearly-en.png` yıllık ürünün Review Information > Screenshot alanına yüklendi. Yıllıktaki eski görsel değiştirildi. İki sayfa yenilendikten sonra Apple CDN üzerinde yeni 1320 × 2868 görsellerin korunduğu doğrulandı; kanıt `Release/AppStore/review-screenshot-upload-20261017.json`. Bu işlem review gönderimi yapmadı.

## 17 Ekim sözleşme ve Netlify yayını

Türkçe/İngilizce gizlilik, ürün koşulları, yardım ve ana sayfa güncel haftalık/yıllık erişim modeliyle Netlify'a yayımlandı. Dağıtım `6ad2a3a0dd89888e79e8bb1c` Published; 12 HTML, 2 asset, robots.txt ve 3 kök URL karşılaştırması geçti (18 adres). Kanıt: `Release/AppStore/netlify-deployment-20261017.json`. Gizlilik metnine şifreli kitaplık önbelleği, favoriler, sağlayıcı bilgileri/görselleri, çevrimdışı indirmeler ve yerel deneme hatırlatması eklendi. Kaynak silmenin indirilmiş dosyaları kaldırmadığı açıklanır. Apple Standart EULA, yenileme/iptal/iade ve park halinde CarPlay video koşulları yer alır.

İlk Business kontrolünde Free Apps Agreement **Active**, Paid Apps Agreement **Pending (New Agreement Available)**, banka hesabı boş, U.S. Tax Questionnaire **Missing Tax Info** ve DSA **Active** idi. Son canlı ödeme kontrolünde Paid Apps Agreement **Pending User Info** oldu ve yeni sözleşme kabul uyarısı kalktı; banka/vergi eksikleri sürüyor. Ödeme yapılandırması çalışması sözleşme kabulü veya banka/vergi formu gönderimi yapmadı. Bu çalışma binary yüklemesi veya yeni App Review gönderimi yapmadı. Canlı ticari ayarların ve metadata karşılaştırmasının son durumu aşağıdadır.

## 17 Ekim canlı yapılandırma kontrolü

Kullanıcı hedef fiyatları, denemeleri, 175 bölgeyi, ortak hizmet seviyesini ve ömür boyu yeni satışının kapatılmasını açıkça onayladı. Aşağıdakiler canlı panellerden kaydedilip yeniden okunarak doğrulandı:

- RevenueCat projesi `7d9b6d16`, Apple uygulaması `app8e29ebec6d`: haftalık ürün `prod03f0c01d41` olarak içe aktarıldı ve `mirivo_pro` erişimine bağlandı. Yıllık ve eski ömür boyu ürünler aynı entitlement’a bağlı kalıyor.
- Varsayılan offering `mirivo_pro` / `ofrng5cc5d706fb`: **ilk yıllık `$rc_annual`, sonra haftalık `$rc_weekly`**. Ömür boyu paket aktif satış teklifinden çıkarıldı; ürün ve erişim eşleştirmesi silinmedi.
- Apple haftalık ürünü `6818888654`: **175/175 bölge**, 17 Ekim başlangıçlı ve bitiş tarihi olmayan **3 günlük ücretsiz introductory offer**; ABD **$2.99**, Türkiye **₺59.99**, 25 Euro bölgesinde **€2.99**, Birleşik Krallık **£2.49** / hafta.
- Apple yıllık ürünü `6818889933`: **175/175 bölge**, aynı başlangıç/bitiş politikasıyla **7 günlük ücretsiz introductory offer**; ABD **$29.99**, Türkiye **₺599.99**, 25 Euro bölgesinde **€29.99**, Birleşik Krallık **£24.99** / yıl. Diğer bölgelerde ABD tutarından Apple’ın hesapladığı eşdeğer fiyatlar kullanıldı. Aylık taksitli 12 ay taahhüt kurulmadı.
- İki abonelik `22438082` grubunda **seviye 1**. İkisi de bireysel **The App Store**, multiseat **Not Allowed**; haftalığın eski Apple Business/School Manager ayarı yıllıkla eşitlendi.
- Ömür boyu `6818966443`: **Remove from Sale**, **0/175 bölge**; sayfa yenilenerek doğrulandı. Geri yükleme desteği ve RevenueCat entitlement bağlantısı korunuyor.
- Haftalık ürünün 22 dilde adı/açıklaması kaydedildi; yıllık Türkçe/İngilizce açıklamaları aynı erişim modeliyle eşitlendi. İki ürünün inceleme notları eski kota/ömür boyu satış anlatımından haftalık/yıllık, deneme uygunluğu ve gerçek fiyatlara geçirildi.
- Mağazanın 22 dildeki açıklamaları hazır güncel metadata dosyalarıyla canlı panelden karşılaştırıldı: **22/22 eşleşti**. Yeni açıklamalarda eski ücretsiz kotalar ve yeni ömür boyu satış iddiası yok. Ana inceleme notunda denemeler artık “configured” olarak belirtiliyor.
- RevenueCat IAP ve App Store Connect API anahtarları **Valid credentials**. Apple production/sandbox bildirim adresleri RevenueCat adresiyle eşleşiyor; henüz alınmış bildirim ve gerçek sandbox satın alma kanıtı yok. Varsayılan restore davranışı **Transfer to new App User ID**.

Açık işler:

- Haftalık ve yıllık ürün inceleme görselleri, 17 Ekim başarılı UI koşusundan alınan ilgili plan seçili İngilizce karelerle güncellendi. Kullanıcı iki dosyanın App Store Connect’e yüklenmesini açıkça onayladı. Her iki görselin kalıcı kaydı sayfa yenilemesiyle doğrulandı; eski kayıt karesi yerine `Release/AppStore/screenshots/subscriptions-20261017/weekly-en.png` ve `yearly-en.png` kullanıldı.
- Seçili App Store build **14** ve sürüm/ürünler hâlâ incelemeye hazır yeni binary ile eşleşmiyor. Yeni build seçilmeli; yeni App Review gönderimi yapılmadı.
- Son Apple Business kontrolünde **Paid Apps Agreement — Pending User Info**; yeni sözleşme kabul uyarısı kalktı. Banka hesabı ve **U.S. Tax Questionnaire — Missing Tax Info** hâlâ eksik. Bu çalışma sözleşme kabulü, banka/vergi formu doldurma veya gerçek para işlemi yapmadı.
- RevenueCat hesap uyarısı $2,500 MTR eşiğinde kart gerektiğini belirtiyor; mevcut MTR $0. Kart eklenmedi.

Kanıtlar: `build/payment-audit-20261017/` içindeki kaydedilmiş haftalık/yıllık fiyat tabloları, ürün DOM kayıtları, 22 dil karşılaştırması ve panel görüntüleri. Yerel StoreKit testleri gerçek Apple sandbox/TestFlight satın alma ve bildirim tesliminin yerine geçmez.

## Haftalık ve yıllık deneme politikası

| Plan | Ürün kimliği | Ücretsiz deneme | ABD hedefi | Türkiye hedefi |
| --- | --- | --- | --- | --- |
| Yıllık | `com.alperbicer.carmirror.pro.yearly` | 7 gün | $29.99 / yıl | ₺599.99 / yıl |
| Haftalık | `com.alperbicer.carmirror.pro.weekly` | 3 gün | $2.99 / hafta | ₺59.99 / hafta |

Euro hedefleri haftalık €2.99, yıllık €29.99; Birleşik Krallık hedefleri haftalık £2.49, yıllık £24.99. Bu fiyatlar 17 Ekim’de canlı mağazada kaydedilip yeniden açılan fiyat tablolarından doğrulandı. Yerel StoreKit dosyası ABD tutarlarını ve iki denemeyi içerir. Uygulama fiyatı StoreKit `displayPrice` üzerinden, denemeyi ürünün gerçek ücretsiz teklifi ve hesap uygunluğu üzerinden gösterir. Mağazada bir ürün yüklenmezse sahte fiyat kartı oluşturulmaz.

Yıllık ilk seçenektir. İki plan aynı Pro erişimini sağlar. Yıllık tasarruf yüzdesi, aynı para birimindeki gerçek fiyatlarla 52 haftalık ödeme üzerinden hesaplanır. Ömür boyu ürün satışta değildir; eski hakları ve geri yükleme desteği korunur.

CarPlay video ve çevrimdışı izleme üstte gösterilir. Araç desteği ve park koşulu CarPlay satırında görünür. Kısa faydalar normal yazı boyutunda tek satırdır: “Süre sınırı yok”, “TV’ye aktar”, “Kaldığın yerden”. Erişilebilirlik boyutlarında okunurluk için dikey düzen kullanılır. Yeni metinler 22 dilde bulunur.

Deneme hatırlatması doğrulanmış ücretsiz denemenin gerçek bitişinden 48 saat önce yerel bildirim olarak planlanır. Kullanıcı izni deneme satın alındıktan sonra istenir; ödeme veya erişim izne bağlı değildir. Deneme hakkı olmayan, doğrulanmamış, bekleyen, iptal edilen veya süresi dolmuş işlem için hatırlatma kurulmaz. Yenileme durumu güncellemelerinde ve uygulama ön plana geldiğinde kontrol yenilenir. Bildirim ayarlarındaki ayrı tercih kapatılırsa bekleyen hatırlatma kaldırılır. Bildirime dokunmak App Store abonelik yönetimini açar; genel duyuru/FCM aboneliği gerekmez.

Uygulama çalışmıyorken App Store’dan yapılan iptal, uygulama yeniden durumu okuyana kadar yerel bildirime yansımayabilir. Bu nedenle bildirim metni “İptal etmezsen…” diye başlar. Bildirimin gösterimi iOS izinlerine ve bildirim ayarlarına bağlıdır. Geç geri yüklemelerde hatırlatma saati geçmişse anlık ve yanlış tarihli bildirim gönderilmez.

App Store Connect bölge/fiyat/deneme ve ortak seviye ayarları ile RevenueCat haftalık/yıllık eşleştirmesi 17 Ekim’de tamamlandı. Grup başına tek introductory offer hakkı StoreKit uygunluğuyla uygulanır. İnceleme görselleri yüklendi; yeni binary ve hesap engelleri tamamlandıktan sonra gerçek sandbox/TestFlight ödeme, geri yükleme ve bildirim teslimi doğrulanmalı.

Yerel doğrulama: 22 dilde 454 anahtar / 9.988 çeviri kontrolü hatasız. Swift core paketinde 69 test çalıştı; 1 atlandı, hata yok. iOS simülatöründe 31 uygulama/StoreKit/hatırlatma testi geçti (`build/paywall-verification-20261016/unit.xcresult`). İmzalı Xcode StoreKit işlemi yıllık denemede sıfır ücret ve 604.800 saniye; ilk yenilemede $29.99 ve yıllık dönem gösterdi. Haftalık üç günlük deneme, grup içinde ikinci denemenin engellenmesi, iptal sonrası hatırlatmanın kaldırılması ve izin/tercih değişiklikleri de doğrulandı. Bunlar yerel StoreKit sonuçlarıdır; canlı mağaza veya gerçek cihazda bildirim teslimi kanıtı değildir.

UI doğrulaması kısmi: ayarlardan Pro ekranına giriş ve geri dönüş testi geçti. Türkçe ekranın erişilebilirlik ağacında üç faydanın aynı satırda olduğu, yıllık $29.99 / 7 gün ve haftalık $2.99 / 3 gün bilgilerinin yüklendiği görüldü. Bu koşuda grup kimliğinin çocuk kimliklerini ezmesi düzeltildi; Türkçe oran `%81` olarak yerelleştirildi. Türkçe/İngilizce/büyük yazılı Arapça plan geçişleri ve `testSevenDayTrialPurchaseFromPaywall` için son uçtan uca doğrulama tamamlanmadı. Önce eşzamanlı derleme/simülatör kullanımı, ardından ayrı kopya ve ayrı aygıtta Xcode'un test hazırlığında kalması nedeniyle son koşu durduruldu. `build/paywall-ui-private-layout-20261016.log` bu hazırlık sınırını kaydeder; başarılı UI testi olarak değerlendirilmemeli. Son kaynaklar derlendi; testleri tekrar çalıştırırken önce yerel kataloğu `StoreKitIntegrationTests/testDisabledSalesCannotStartPurchase` ile başlatmak gerekir.

> 15 Ekim 2026 güncellemesi: Apple CarPlay Video yetkisi etkinleştirildi; CarPlay video sahnesi, ekran paylaşımı ve bağlantı hatırlatması geri getirildi. Güncel dağıtım durumu DEPLOYMENT.md içindedir. Aşağıdaki eski build kayıtları tarihseldir.

# Mirivo Pro — 5 Ekim 2026

7 Ekim yerel takip: araç modu ücretsiz günlük izleme bütçesi içindedir. Destek sitesi kaynak metinleri bu davranışla ve dosyadan kaynak/hesap bitiş bilgisinin yerel saklanmasıyla güncellendi; yeniden üretilen ZIP yayımlanmadı. Güncel yerelleştirme doğrulaması 22 dil × 280 anahtar, 6160 çeviri, 0 hata. [Kaynak yöntemleri ve doğrulama](SOURCE_METHODS_2026-10-07.md).

Mirivo henüz yayımlanmadı ve eski satın alma yok. Satış modeli yalnız yıllık ve ömür boyu Pro; aynı özellikleri açar. Haftalık plan koddan, StoreKit dosyasından ve aktif RevenueCat teklifinden çıkarıldı. Ücretsiz kullanım korunur; her iki sürüm reklamsızdır.

| Erişim | Ücretsiz | Pro |
| --- | --- | --- |
| Günlük izleme | 2 saat, cihaz yerel bütçesi | Sınırsız |
| Kayıtlı kaynak | 1 | Sınırsız |
| Ekran yayını | Oturum başına 10 dakika | Mirivo süre sınırı yok |
| Araç modu | Günlük 2 saatlik izleme bütçesi içinde açık | Sınırsız izleme |
| Cihaz içi canlı altyazı | Pro ekranı | Desteklenen cihazlarda açık |

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

5 Ekim akşamı: Gelecek sürümlerde hiçbir zaman reklam olmayacağı sözü 22 dilin uygulama kataloğundan kaldırıldı. Türkçe/İngilizce mağaza tanıtımı kaydedilip doğrulandı; destek sitesinin ad-only değişikliği `6ac403313eda88f818df1f24` dağıtımında yayında. Yeni 1.0 (12) arşivi ve IPA Apple'a yüklendi. 6 Ekim kontrolünde Validated, sürüm 1.0'a kaydedilmiş ve kendi internal grubunda Testing. İki güncel Pro inceleme görseli yüklenip yenileme/görsel kontrolle doğrulandı; ürünler aynı üç öğelik taslakta. TR/EN TestFlight kabul notları kayıtlı. RevenueCat teknik kontrolü tamamlandı ve yedi App Privacy türünün tüm cevapları taslağa kaydedilip yenilemeyle doğrulandı; Publish açık, son yayın hesap sahibine ait. Güncel ayrıntılar readiness/owner belgelerinde.
