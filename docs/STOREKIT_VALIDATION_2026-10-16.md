# Yerel StoreKit doğrulaması — 16 Ekim 2026

> Bu kayıt, aynı günün önceki üç günlük yıllık teklifine aittir. Sonraki haftalık 3 gün / yıllık 7 gün politikası ve doğrulama sonuçları [PRO_RELEASE.md](PRO_RELEASE.md) içindedir. Güncel satın alma UI testi `ProductUITests.testSevenDayTrialPurchaseFromPaywall` adını kullanır.

Bu çalışma yalnız yerel uygulama, Xcode ve simülatör test ortamını kapsar. RevenueCat veya App Store Connect yapılandırması, canlı fiyat/ürün/teklif değiştirilmedi. Satın alma testlerinde RevenueCat anahtarı derleme argümanıyla boş bırakıldı; aynı koruma `scripts/test_app.mjs` içine eklendi.

## Kök neden ve düzeltme

İlk `SKInternalErrorDomain Code=3` kaydının altında StoreKit servisi şu somut nedeni yazdı: `com.alperbicer.carmirror is not installed for development` (`build/storekit-session-initial-20261016.log`). Debug simülatör derlemesinde `get-task-allow` eksikti.

`Config/SimulatorDebug.entitlements`, normal uygulama yetkilerini koruyup yalnız `get-task-allow` ekler. Proje ve proje üreticisi bu dosyayı yalnız ana uygulamanın **Debug + iphonesimulator** koşulunda seçer. Release ve fiziksel cihaz yapılandırması `Config/App.entitlements` kullanmaya devam eder.

Satın alma sonrasında StoreKit 2 erişim önbelleğinin imzalı işlemden kısa süre sonra güncellenmesi de gerçek testlerde görüldü. Uygulama doğrulanmış işlemi bitirir ve erişimi hemen görünmezse en fazla yaklaşık iki saniye yeniden sorgular. Böylece başarılı satın alma için erken bir doğrulama hatası gösterilmez; erişim yine StoreKit'in doğrulanmış entitlement sonucundan gelir.

Test oturumu ayarının uygulandığı kontrol edilir; uygulanamıyorsa satın almaya geçilmez. Test servisinin silme/iade/bitiş işlemlerinden sonra StoreKit önbelleğinin güncellenmesi sınırlı süreyle beklenir. Yerel `.storekit` dosyası otomatik ödeme onayı kullanır; bu dosya ana uygulamanın Release kaynaklarına eklenmez.

## Doğrulanan işlemler

Xcode 27.0 ve iOS 26.5 üzerinde altı StoreKit entegrasyon testi geçti (`build/storekit-validation-20261016.log`, ilgili StoreKitIntegrationTests bölümü):

- Yıllık üründe yeni kullanıcı için üç günlük deneme uygunluğu ve gerçek `Product.purchase()` çağrısı.
- StoreKit tarafından doğrulanmış, `environment=Xcode` olan ücretsiz introductory işlem: fiyat **0**, süre **259.200 saniye**.
- Denemeden sonraki zorlanan yıllık yenileme: fiyat **19.99 USD**, süre **31.536.000 saniye**. Yerel test fiyatı değişmedi.
- Etkin üyeliği geri yükleme; deneme sırasında yenilemeyi iptal edince kalan erişimin korunması; süre sonunda erişimin kapanması.
- Eski ömür boyu satın alımın geri yüklenmesi ve iadesi; satış kapalıyken satın alma başlatılmaması; Keychain işlemleri.

Xcode 27.1 ve iOS 26.5 üzerinde yeniden doğrulandı (`build/development-final-20261016.log`): altı StoreKit işlem testi ve bir geliştirme erişimi testi geçti. Geliştirme testi ücretsiz erişimin satın alınmış ürün/entitlement oluşturmadan açılıp kapandığını doğrular.

`ProductUITests.testThreeDayTrialPurchaseFromPaywall` iki ayrı koşuda başarılı oldu (`build/development-validation-20261016.log`, `build/development-final-20261016.log`). Ekranda üç günlük deneme ve yıllık fiyat görüldü, gerçek satın alma düğmesine dokunuldu ve ardından `Pro etkin` durumu doğrulandı. UI testi `-mirivo-ui-playback-access` veya geliştirme erişimi kullanmaz. Ekran kayıtları `build/development-final-review-20261016/` içindedir.

Dağıtım/test araçları: **26/26** test başarılı (`build/development-script-tests-20261016.log`). Debug ve Release derleme koşullarıyla ayrı çalıştırılan ortak erişim politikası kontrolü de başarılı: `build/development-policy-check/debug.log` ve `release.log`. Release, diskte geliştirme tercihi açık olsa bile erişim sağlamaz.

## Xcode güncellemesi

Doğrulama sürerken Xcode 27.0’dan **27.1 (27A9275)** sürümüne güncellendi. Eski CoreSimulator bileşeni nedeniyle geçici olarak ilk kurulum bekledi. Sistem bileşenleri tamamlandıktan sonra `xcodebuild -checkFirstLaunchStatus` başarılı oldu, iOS 26.5 simülatörü açıldı ve yukarıdaki testler yeniden çalıştırıldı. Kurulum engeli artık yoktur.

İşlem ve ödeme ekranını birlikte yeniden doğrulamak için:

```sh
node scripts/test_app.mjs B952AA0F-C81F-49A2-83F3-CEBE9D048739 \
  --only-testing=MirivoTests/StoreKitIntegrationTests \
  --only-testing=MirivoUITests/ProductUITests/testThreeDayTrialPurchaseFromPaywall \
  --keep-cache
```

StoreKit entegrasyon testleri önce yerel satın alma geçmişini sıfırlar; ardından UI testi üç günlük teklifin ve mevcut yıllık fiyatın görünmesini, ödeme düğmesine dokununca Pro'nun etkinleşmesini kontrol eder. Bu sonuçlar yerel StoreKit ortamına aittir; canlı App Store/TestFlight satın alma kanıtı değildir.
