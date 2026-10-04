# Mirivo Pro — 4 Ekim 2026

Kullanıcı kararı: ilk App Review sürümü Pro ile gönderilecek. `MIRIVO_PRO_SALES_ENABLED = YES`; Pro yakında ifadeleri kaldırıldı. Ücretsiz ve Pro sürümler reklamsızdır.

| Erişim | Ücretsiz | Pro |
| --- | --- | --- |
| Günlük izleme | 2 saat, cihaz yerel bütçesi | Sınırsız |
| Kayıtlı kaynak | 1 | Sınırsız |
| Ekran yayını | Oturum başına 10 dakika | Mirivo süre sınırı yok |
| Araç modu ve cihaz içi canlı altyazı | Pro ekranı | Desteklenen cihazlarda açık |

Pro içerik, IPTV hesabı, CarPlay Video yetkisi, araç uyumluluğu veya DRM erişimi sağlamaz.

| Ürün | Kimlik | Dönem | Başlangıç USD fiyatı |
| --- | --- | --- | --- |
| Haftalık | `com.alperbicer.carmirror.pro.weekly` | 1 hafta, yenilenir | 1.99 |
| Yıllık | `com.alperbicer.carmirror.pro.yearly` | 1 yıl peşin, yenilenir | 19.99 |
| Ömür boyu | `com.alperbicer.carmirror.pro.lifetime` | Tüketilemeyen, tek ödeme | 39.99 |

Uygulama fiyatları StoreKit'ten alır; yerel test fiyatlarını satış fiyatı olarak kodlamaz. Haftalık ve yıllık aynı hizmet seviyesine yerleştirilmelidir. Aylık taksitli 12 ay taahhüt planı kullanılmaz. Fiyatlar App Review gönderilmeden önce sahibin son onayına tabidir.

## Satın alma ve RevenueCat

StoreKit 2 `Transaction.currentEntitlements` doğrulanmış erişimi belirler. İade, abonelik bitişi ve yükseltme yerel erişim hesabında işlenir. ReplayKit uzantısı kendi StoreKit kontrolünü yapar; RevenueCat SDK'sı uzantıya eklenmez. Bekleyen/doğrulanamayan işlemler erişim açmaz. Uygulama ön plana döndüğünde erişim yenilenir.

RevenueCat 5.x ana uygulamaya eklenmiştir. Mevcut StoreKit satın alma akışı korunur; RevenueCat [uygulamanın işlemleri tamamladığı modda](https://www.revenuecat.com/docs/migrating-to-revenuecat/sdk-or-not/finishing-transactions) gözlem yapar. Yapılandırma yalnız `appl_` ile başlayan public Apple SDK anahtarıyla açılır. Gizli anahtar veya Test Store anahtarı uygulamaya konulmaz. Erişim RevenueCat ağ isteğine bağlı değildir.

RevenueCat projesi: [Mirivo](https://app.revenuecat.com/projects/7d9b6d16/overview). Başlangıç Test Store offering'i weekly/yearly/lifetime ve Mirivo Pro erişimiyle oluşturuldu. **Bu Test Store, gerçek App Store bağlantısı değildir.** App Store uygulaması kaydedilirken zorunlu In-App Purchase Key ID ve Issuer ID eksik olduğu bildirildi. Anahtar oluşturma/servise yetki verme sahibin onayına bırakıldı.

Onaydan sonra RevenueCat App Store uygulamasını `com.alperbicer.carmirror` ile kaydet; gerçek Apple ürünlerini Mirivo Pro erişimine ve default offering'in weekly/yearly/lifetime paketlerine bağla. Public Apple SDK anahtarını git dışında tutulan `Config/Local.xcconfig` dosyasına `MIRIVO_REVENUECAT_API_KEY = appl_...` olarak ekle. Test Store kimlikleri yerine yukarıdaki gerçek ürün kimlikleri kullanılmalıdır.

## Doğrulama ve kalan işlemler

Kaynak sürüm 1.0 (8); önceki TestFlight 1.0 (7) kaydından ayrı build numarası kullanılır.

42 Swift testi ve imzasız iOS Simulator derlemesi geçti. 22 dil × 245 anahtar, 12 HTML, plist/yerel bağlantı ve ZIP eşleşmesi kontrolü geçti. Bu sonuçlar Apple sandbox veya gerçek satın alma kanıtı değildir.

App Store Connect canlı kayıtları: Mirivo Pro grubu `22438082`, haftalık `6818888654`, yıllık `6818889933` ve ömür boyu tüketilemeyen ürün `6818966443`. Üç ürünün Türkçe/İngilizce görünen adları ve açıklamaları hazır. Ömür boyu ürün ABD fiyatı 39.99 USD, 175 ülke/bölge fiyat eşlemesi ve tüm ülke erişimiyle kaydedildi; inceleme notu yeniden açılarak doğrulandı. Grup adı Türkçe ve ABD İngilizcesinde Mirivo Pro / uygulama adı Mirivo olarak kaydedildi.

Sürüm 1.0 Türkçe/İngilizce açıklama, tanıtım ve anahtar sözcükleri kaydedildi. İnceleme notları Pro planlarını ve CarPlay Audio sınırını açıklar. Sign-in required kapatıldı; yayınlama manuel seçildi. Kişisel iletişim ve copyright alanları boş bırakıldı. Ana açıklamalar CarPlay Audio paketinin araçta video/yansıtma sunmadığını belirtir.

**Teknik kalan:** haftalık ve yıllık portalda hâlâ ayrı seviyelerde (1/2). Edit Level diyalogunda tekrarlanan sürükleme girişimleri düzeyi değiştirmedi; kaydetmeden kapatıldı. İki plan aynı hizmeti sunduğundan aynı seviyede gruplanması ve tablodan doğrulanması gerekir. İnceleme ekran görüntülerinin yüklenmesi de henüz yapılmadı.

Kişisel/son onay alanları: vergi, banka, Paid Applications Agreement, inceleme iletişim bilgileri, RevenueCat Apple anahtarı yetkilendirmesi, gizlilik beyanı ve Submit for Review. Bu alanlara bilgi girilmedi, sözleşme kabul edilmedi, incelemeye gönderilmedi.

Yerel destek sitesi ve offline belgeler güncellendi. `Release/mirivo-netlify.zip` yeni içeriği taşır; canlı Netlify sitesi henüz bu sürüme güncellenmedi. TestFlight metadata taslakları da Pro akışına göre düzenlendi.

4 Ekim yeniden denemesi: iOS 26.5 simülatörü açıldı. `ProductUITests/testTurkishProductAndOfflineLegalFlows()` ve Keychain round-trip testi geçti (`build/pro-resumed-tests.xcresult`). Üç StoreKit testi başarısız: ürünler boş döndü / `notEntitled`. Xcode IDE üzerinden fixture eşitlenince ürünler yüklenebildi ve disabled-sales testi geçti; fakat SKTestSession yapılandırma ve işlem çağrıları `SKInternalErrorDomain Code=3` verdi, lifetime testi tamamlanmadı. CLI eşitleme sonrası tekrar denemesi ilerlemedi ve durduruldu. iOS 27 karşılaştırmasında Device Hub görüntü bağlantısı zaman aşımına uğradı; başarılı test sonucu alınmadı. Apple forumunda [aynı CLI/StoreKitTest semptomu](https://developer.apple.com/forums/thread/826971) raporlanmış olsa da burada satın alma akışının doğrulandığı anlamına gelmez.

Gerçek sandbox satın alma, geri yükleme, iade, abonelik bitişi ve ReplayKit Pro erişimi doğrulanmadan incelemeye hazır sayılmaz.

Sekiz düzenlenmemiş gerçek UI görüntüsü `Release/AppStore/screenshots/pro-qa/` içinde. `05-mirivo-pro-tr.png` Pro özelliklerini gösterir, fiyat/plan listesi boş olduğundan tamamlanmış satın alma ekranı kanıtı değildir; ürünler yüklendiğinde yeniden çekilmelidir. Kaynak cihaz/runtime/result bilgisi provenance.json dosyasındadır. Yükleme yapılmadı.

## Sahibin onayına ayrılan somut işlemler

- RevenueCat Apple anahtarı oluşturma/seçme ve servise yetki verme; ardından gerçek App Store uygulaması/ürün eşlemesi ve public `appl_` anahtarının yerel build ayarına alınması.
- Hazır `Release/mirivo-netlify.zip` paketini mevcut `mirivo-support` sitesine yayınlama; canlı sürüm halen eski.
- Plan/fiyat ekranı doğrulandıktan sonra inceleme görsellerini Apple’a yükleme.
- Final RevenueCat yapılandırmasından sonra yeni build numarasıyla IPA üretme ve Apple’a yükleme.
- Fiyat ve gizlilik beyanı onayı; sözleşme/vergi/banka/iletişim alanları; Add for Review ve Submit for Review.

Tarayıcı araçlarının dosya yükleme ve güvenlik yetkilendirme onay kuralları nedeniyle bu son adımlar sahibin kapsam dışında bıraktığı onay listesine ayrıldı. Yalnız yerel hazırlık ve kayıt düzenlemeleri tamamlandı.

Yerel Release arşivi başarıyla oluşturuldu ve script tarafından imza/entitlement doğrulaması yapıldı: `/Users/alperbicer/Documents/projects/private/car-mirror/build/deploy/2026-10-03T22-59-20-258Z-archive-dd4ddd/CarMirror.xcarchive`. Sürüm 1.0 (8), CarPlay Audio. Bu yerel arşiv App Review gönderimi veya dağıtım IPA doğrulaması değildir.

App Store IPA dışa aktarımı başarılı; yerel dağıtım paketi script tarafından doğrulandı: `build/deploy/2026-10-03T23-01-22-947Z-export-cc741c/ipa/CarMirror.ipa`. Apple’a yüklenmedi. RevenueCat anahtarı eklendikten sonra arşiv yeniden üretilmeli; bu IPA boş RevenueCat yapılandırmasıyla StoreKit satın alma akışını içerir.
