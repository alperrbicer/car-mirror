# Ekran düzeni ve üyelik taslağı — 16 Ekim 2026

Bu değişiklikler yereldir. Kullanıcı paket kararını yeniden değerlendirebileceği için RevenueCat, App Store Connect, canlı fiyatlar, mağaza metinleri ve destek sitesi değiştirilmedi; derleme yüklenmedi veya yayımlanmadı.

## Ekranlar

- Mirivo’nun koyu zemin ve mint vurgu dili korunur. Ana sayfa kaynak oynatmayı, Smart TV’yi ve CarPlay’i öne çıkarır; iki ana bölümün gezinme denetimi daha kompakt hale gelir.
- Kaynaklara doğrudan geçiş ve CarPlay rehberini seçili açan ayrı giriş eklendi. Smart TV girişi CarPlay bağlıyken TV aramasını açar; araç bağlantı durumu üstteki ortak durum düğmesinden erişilebilir.
- Boş kaynak ekranındaki M3U, doğrudan bağlantı, Xtream ve dosya seçenekleri ilgili formu açar. Seçilen tür, formun sunumuyla birlikte taşınır; ilk açılışta başka türün görünmesine yol açan durum ayrılığı kaldırıldı. Kayıtlı kaynaklarda ekleme düğmesi uzun içerik listelerinden önce yer alır.
- Bağlantı listesinde yinelenen Google Cast bölümü birleştirildi; satır zeminleri diğer formlarla eşitlendi. Ayarlarda ekran paylaşımı seçenekleri genel tercihlerden ayrıldı ve bağlantı rehberleri eklendi.
- Ana sayfadaki kalite/ses değerleri değiştirilebilir menülere dönüştü. Paylaşım formları ortak içerik genişliği kullanır; slayt süresi menüsü büyük yazıda taşmaz. Yön bildiren gezinme simgeleri sağdan sola düzene uyar.
- Bağlantı/dosya satırlarının dokunmasını engelleyen dekoratif çerçeve düzeltildi. Üyelik ekranından dönüldüğünde bağlantı adresi ve slayt seçimi korunur. Ekran paylaşımı düğmesinin kontrastı ve URL alanlarının yer tutucuları ortak görünüme uyar.
- Onboarding’in mevcut yerel sayfalama ve erişilebilirlik düzeltmeleri korunur. Son sayfa iPhone, TV ve CarPlay’i birlikte tanıtır. CarPlay video için araç desteği ve park koşulu görünürdür.
- Oynatıcı, kategori/dizi listeleri, medya bilgileri, indirilenler, dil/bildirim/altyazı ayarları ve zorunlu güncelleme ekranları kaynak düzeyinde gözden geçirildi. Oynatıcı geometrisi ve video yüzeylerinin yaşam döngüsü değiştirilmedi.

## Yerel üyelik modeli

- Satış listesi yalnız mevcut yıllık ürünü içerir: `com.alperbicer.carmirror.pro.yearly`. Tutar StoreKit `displayPrice` değerinden okunur. Yerel ABD test fiyatı $19.99 olarak korunur.
- Yerel StoreKit dosyasında yıllığa üç günlük ücretsiz introductory offer eklendi. Ekran ancak StoreKit üç günlük ücretsiz teklifi ve kullanıcı uygunluğunu birlikte bildirirse deneme sunar. Aksi halde gerçek yıllık fiyatla normal abonelik gösterir.
- Ömür boyu paket satış ekranından çıkarıldı. Daha önce edinilmiş ömür boyu hakları tanımak ve geri yüklemek için ürün kimliği/entitlement desteği korunur. Test dosyasında bu eski ürün yalnız geri yükleme/iade testleri için bulunur.
- Günlük 1/2 saatlik sayaçlar, kota uyarıları ve gizli kota sıfırlaması kaldırıldı. Kaynak ekleme ve gezinme üyelik öncesinde kullanılabilir. Oynatma, indirme ve ekran paylaşımı etkin deneme veya doğrulanmış Pro erişimi gerektirir. Ayrı on dakikalık ücretsiz paylaşım oturumu yoktur.
- Üyelik sona ererse etkin oynatma durur; yeniden üyelikte tekrar oynatma mümkün olur. ReplayKit uzantısı erişimi kendi StoreKit kontrolüyle doğrular.
- Pro ekranı kısa fayda kartları, seçili yıllık plan, deneme zaman çizgisi ve sabit satın alma alanı kullanır. Erişilebilirlik yazı boyutlarında satın alma alanı içeriğe katılır; büyük bir sabit panelin sayfayı kapatması önlenir. Deneme sonrası tutar, yenilenme, iptal, geri yükleme ve yasal bağlantılar erişilebilirdir. Uygulama içi hatırlatma taahhüdü eklenmedi.
- Eski oynatıcı UI testleri açık bir DEBUG erişim argümanıyla çalışır. Üyelik engeli testleri bu argümanı kullanmaz; StoreKit satın alma testleri gerçek yerel StoreKit durumunu kullanır. Bu ayrım gerçek satın alma başarısı olarak yorumlanmamalıdır.

## Doğrulama

- iOS Simulator uygulama ve uzantı derlemesi başarılı.
- Swift çekirdek/medya koşusu: 69 test, bir ortam atlaması, sıfır hata (`build/design-core-20261016.log`).
- Dağıtım araçları: 26 test geçti (`build/design-scripts-20261016.log`).
- Yerelleştirme: 22 dil, 404 anahtar, 8.888 değer; sıfır statik hata (`build/design-static-final-20261016.log`).
- iOS 26.5 üzerinde üç üyelik davranış testi geçti: telefon/CarPlay erişim engeli, eski günlük sayaçların etkisizliği ve üyelik sona erince oynatmayı durdurup yenileme sonrası tekrar başlatma (`build/design-ui-final-20261016.log`).
- Hedefli 11 farklı arayüz senaryosunun son koşuları başarılı: başlangıç akışları, Türkçe/İngilizce/Arapça Pro ekranı, erişilebilirlik yazı boyutları, ana sayfa/CarPlay rehberi, dört kaynak türü, üyelik öncesi kaynak hazırlama, üyelik engeli, hızlı bağlantı doğrulaması, form verisinin korunması, ayarlar ve destek bağlantıları. Son üç ekran testi `build/design-ui-complete-20261016.log` içinde sıfır hatayla tamamlandı; diğer başarılı sonuçlar `build/design-ui-final-20261016.log` ve `build/design-ui-recheck-20261016.log` içinde. Önceki koşulardaki form türü ve dokunma hataları düzeltilerek tekrar doğrulandı.
- İlk StoreKit koşusundaki `SKInternalErrorDomain Code=3`, sonraki araştırmada Debug simülatör geliştirme yetkisine kadar izlendi ve düzeltildi. Üç günlük ücretsiz işlem, satın alma, ücretli yıllık yenileme, iptal ve geri yükleme altı entegrasyon testiyle doğrulandı. Yeni üç günlük teklif ve gerçek ödeme düğmesinden Pro etkinleşmesi, Xcode 27.1 kurulumu tamamlandıktan sonra iki ayrı UI koşusunda doğrulandı. Güncel ayrıntılar: [StoreKit doğrulama notları](STOREKIT_VALIDATION_2026-10-16.md).
- Güncel görsel kayıtlar `build/design-review-final-20261016/` altında: ana sayfa, kaynaklar ve dört kaynak formu, Pro TR/EN/AR, onboarding, ayarlar ve bağlantı rehberleri. Ayar görselleri ilgili güncel `.xcresult` paketinden çıkarıldı. `git diff --check` temiz; başlangıçta staged olan iki dosyanın index içeriği korundu.

Canlı mağazadaki teklife bu çalışmada dokunulmadı. Paket kararı kesinleştikten sonra mağaza teklifi, destek sitesi ve mağaza açıklamaları birlikte değerlendirilmeli; gerçek sandbox/TestFlight satın alma, iptal ve geri yükleme ayrıca doğrulanmalıdır.

## Sürüm, tanıtım ve geliştirme erişimi

- `Sürüm` alanı kurulu uygulamanın gerçek Bundle sürümünü okumaya devam eder. Sürekli `1.0 (8)` görünmesinin nedeni `Config/Base.xcconfig` değerinin 8 kalması ve install/simulator komutlarının archive gibi numara ayırmamasıydı. Mevcut yerel sayaç 18 ile proje eşitlendi. Bundan sonraki install/simulator/archive komutları aynı monoton sayacı kullanır ve Base.xcconfig değerini günceller. Açık `--version` seçimi de varsayılana kaydedilir. Başarısız derleme ayrılan sayıyı tüketebilir; tekrar kullanılmaz.
- Ayarlar’daki `Tanıtımı yeniden göster`, ayar sayfası kapandıktan sonra ilk tanıtım sayfasını açar. Tamamlama durumu sıfırlanır; kaynaklar ve üyelik silinmez.
- Ayarlar > Geliştirme altındaki `Ücretsiz ve sınırsız geliştirme erişimi` varsayılan olarak kapalıdır. Yalnız Debug derlemelerinde bulunur; Release önceden kaydedilmiş değeri de yok sayar. Uygulama ve ReplayKit aynı yerel tercihi kullanır; doğrulanmış üyelik veya ürün kimlikleri değiştirilmez. Ödeme testleri bu anahtarı kullanmaz.
- Ana sayfada kalite/ses menülerinin özel değer etiketi ve aynı genişlikte ok simgesi vardır. Büyük erişilebilirlik yazısında başlık ve kontrol alt alta geçer; uzun değerler gerektiğinde satır yüksekliğini artırır.

Bu ek düzenlemelerin son doğrulaması: 26 betik testi, 22 dilde 407 anahtar/8.954 değer kontrolü, altı StoreKit işlemi ve bir geliştirme erişimi testi başarılı. Dört farklı UI senaryosunun son koşuları başarılı: ayarlar/rehber (`build/development-validation-20261016.log`), geliştirme anahtarı ve onboarding + gerçek ödeme düğmesi (`build/development-final-20261016.log`), normal/Accessibility XXXL kalite-ses hizalaması (`build/development-home-20261016.log`). İlk koşulardaki kısmen görünür anahtar dokunması ve iç içe menü sorunları düzeltilerek tekrar doğrulandı. Son başarılı ekran kayıtları `build/development-review-final-20261016/` altında. Debug/Release ortak erişim politikası ayrı derlenip çalıştırıldı; Release kaydedilmiş geliştirme iznini yok saydı. Fiziksel cihaz veya canlı mağaza satın alımı bu doğrulamanın kapsamı değildir.
