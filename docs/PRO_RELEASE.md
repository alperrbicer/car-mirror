# Mirivo Pro hazırlığı

2 Ekim 2026 kullanıcı kararı: Pro altyapısı hazırlanacak, satış daha sonra açılacak. İlk sürümde tüm mevcut özellikler açık ve hiçbir sürümde reklam olmayacak. `Config/Base.xcconfig` içindeki `MIRIVO_PRO_SALES_ENABLED = NO` ana uygulama ve yayın uzantısına birlikte aktarılır. Pro ekranında fiyat veya satın alma düğmesi gösterilmez. `PurchaseStore.purchase` de bu ayarı doğrular; yalnız arayüzden gizlemekle yetinilmez.

Hazırlanan özellikler: M3U/doğrudan yayın/Xtream kaynak kitaplığı, araç modu, ekran paylaşımında cihaz içi canlı altyazı, uygulama süre sınırı olmadan yayın. Üçüncü taraf içerik aboneliği ve desteklenmeyen araç/DRM erişimi satışa dahil değildir. Araç modu telefonda ve gerçek harici ekranda büyük oynatıcı kontrolleridir; CarPlay şablonları Apple'ın düzenini kullanır.

| Ürün kimliği | App Store türü | Dönem |
| --- | --- | --- |
| `com.alperbicer.carmirror.pro.weekly` | Otomatik yenilenen abonelik | 1 hafta |
| `com.alperbicer.carmirror.pro.yearly` | Otomatik yenilenen abonelik | 1 yıl |
| `com.alperbicer.carmirror.pro.lifetime` | Tüketilemeyen satın alma | Tek ödeme |

Haftalık/yıllık ürünler aynı abonelik grubunda aynı hizmet düzeyinde olmalıdır. Gerçek fiyatlar, ülkeler ve varsa teklif koşulları henüz seçilmedi; kodda satış fiyatı veya promosyon uydurulmadı. `.storekit` dosyasındaki tutarlar yalnızca yerel test senaryoları içindir ve uygulama paketine eklenmez.

StoreKit 2 doğrulanmış `Transaction.currentEntitlements` sonuçları erişimi belirler. Bekleyen veya doğrulanamayan satın alma erişim açmaz. İşlem güncellemeleri, geri yükleme, iade ve abonelik bitişi işlenir. Yayın uzantısı ücretli model açıkken yeni yayın başında kendi doğrulanmış erişim kontrolünü yapar. Apple'ın faturalama ek süresi `currentEntitlements` tarafından desteklenir. [Apple erişim modeli](https://developer.apple.com/documentation/storekit/transaction/currententitlements)

İleride satış etkinleştiğinde mevcut politika ücretsiz kullanıcıya bir kaynak ve oturum başına 10 dakika verir; Pro'da bu sınırlar yoktur. Bu sınırlar şu anda uygulanmaz. Ticari açılıştan önce kullanıcıyla son paket kararı kesinleştirilir; fiyat/ürün kaydı, sandbox testi ve araç kabul kanıtı tamamlanır. Ardından ücretsiz ilk sürümü anlatan Pro ekranı/web metinleri güncellenerek tek yapılandırma değeri açılır.

`node scripts/test_app.mjs SIMULATOR_UDID` StoreKit ve arayüz testlerini çalıştırır. iOS 26.5 StoreKit Test ortamında Apple'ın bildirdiği yapılandırma sorunu vardır; iOS 27 bu makinede denendi, ancak oturum başlayamadı. Bu nedenle Pro satın alma testleri henüz geçmiş sayılmaz; destekleyen ve çalışan bir StoreKit Test ortamında tamamlanmalıdır. `--ui-only` seçeneği satın alma testlerini atlayıp iOS 26.5 üzerinde doğrulanan arayüz akışlarını çalıştırır. [Apple DTS açıklaması](https://developer.apple.com/forums/thread/826971)
