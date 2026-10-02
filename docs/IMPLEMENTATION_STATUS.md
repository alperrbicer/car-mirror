# Uygulama durumu · 2 Ekim 2026

Kaynak sürüm: **0.1.0 (4)**. Bu çalışma, ilk araç çıkışını ölçmek için gereken uygulama altyapısını ve ilk görsel yönü hazırlar. EV6 ekranında yansıtma, eşzamanlı ses veya App Store yayını tamamlanmış değildir.

## Uygulananlar

- Ana ekran gerçek yakalama, araç bağlantısı ve harici oynatma sinyallerinden durum üretir. Ekran yakalamanın başlaması tek başına “paylaşım etkin” sayılmaz. Eski oturumun oynatıcısı yeni oturuma başarı atayamaz.
- Durdurma, duraklama, eski heartbeat, oynatma hatası, test bitişi ve 15 saniyede harici oynatma kurulamaması ele alındı. Hata/bitirişte oynatıcı, ses oturumu ve Now Playing bilgisi temizlenir. Yeniden deneme kullanıcı eylemidir.
- Ana uygulama ve ReplayKit uzantısı aynı yakalama oturum kimliğiyle türleri belirlenmiş olaylar yazar. Son 10 oturum için en fazla 5 MiB JSONL saklanır; eşzamanlı erişim dosya kilidiyle korunur. URL, erişim anahtarı, hesap, cihaz adı, ekran/ses içeriği ve serbest hata açıklaması raporlanmaz.
- Destek alanına JSON rapor paylaşımı ve kayıt temizleme eklendi. Kayıtlar otomatik gönderilmez. Sürüm bilgisi rapora eklenir.
- Koyu SwiftUI ana ekran, ekran logosu, uyumlu sistem açılış zemini ve küçük ayarlar alanı uygulandı. Büyük metinde dekoratif görseller kaldırılır ve ana eylem görünür kalır. Son marka/ikon ve açılış geçişi seçime bağlıdır.
- Debug sürümüne, ReplayKit/ağdan bağımsız 15 saniyelik sayaç videosu ve iOS gerçekten harici ekran sahnesi sağladığında çalışan hareketli desen eklendi. Test kontrolleri Release arayüzünde bulunmaz. Bunlar aktarım yolunu ölçer; EV6 desteği varsayılmaz.
- Simülatör kurulum komutu App Group erişimi için ad hoc imzalanır. Fiziksel cihaz ve dağıtım profili kontrolleri korunur.

## Yerel doğrulama

| Kontrol | Sonuç / kanıt |
| --- | --- |
| Swift çekirdek ve medya testleri | 19 geçti: durum tutarlılığı, eski oturum, kayıt mahremiyeti, eşzamanlı yazım, saklama sınırı, temizleme, HLS/HTTP ve test videosundaki değişen kareler. `build/product-foundation-tests.log` |
| Kurulum araçları testleri | 12 geçti. Cihaz seçimi, profil/yetki kontrolleri, başarısız derlemede kurulumun durması ve simülatörde ad hoc imzalama. `build/product-foundation-script-tests.log` |
| Debug simülatör | Derleme, ad hoc imza, kurulum ve açılış başarılı. `build/product-foundation-simulator.log` |
| iOS Release | İmzasız cihaz derlemesi başarılı. Profil, fiziksel kurulum veya App Store sonucu değildir. `build/product-foundation-release.log` |
| Canlı uygulama kayıtları | Simülatörde App Group içinde `appOpened`, `appForegrounded`, `playbackState` olayları oluştu. |
| Yerel tasarım karşılaştırması | Üç isim ve ekran durumu kontrolleri denendi; 320 ve 1280 px genişliklerde yatay taşma yok. Chrome kullanılmadı. |
| Native görünüm | Ana ekran simülatörde standart ve en büyük erişilebilir yazı boyutunda incelendi. `build/qa/home-portrait.png`, `build/qa/home-large-text.png` |
| Yapılandırma | Info.plist ve entitlement plist doğrulaması, `git diff --check` geçti. |

Simülatör ortamı iPhone 17 Pro Max / iOS 27'dir; iPhone 16 Pro fiziksel görünüm testi yerine geçmez. Device Hub'ın arayüz kontrolü yanıt vermediği için ayarlar, sistem paylaşım ekranı, ekranı döndürme ve test düğmelerinin dokunma akışı uçtan uca doğrulanamadı. Bu maddeler geçilmiş olarak sayılmıyor.

## Kullanıcıya hazır tasarım

- [İsim ve iki tema karşılaştırması](../Design/brand-directions.html)
- [İncelenmiş görsel](../Design/brand-directions-preview.jpg)
- [İki ekran logosu](../Design/mirror-mark.svg) ve [açık çerçeve logosu](../Design/frame-mark.svg)

Mirivo önerilen ilk adaydır; Yansio ve Ekrivo alternatiflerdir. Ad rezervasyonu ve marka uygunluğu tamamlanmadı. Çalışma adı ve bundle kimlikleri korunur.

## Bekleyen araç testi

İlk ortam: iPhone 16 Pro, 2024 Kia EV6 orijinal ekran, YouTube ve Smarters Player. Hem doğrudan kablo hem markasız kablosuz adaptör kullanılıyor. CarTV'nin her iki bağlantıdaki sonucu aynı oturumlarda ayrı ayrı karşılaştırılacak.

1. Kullanıcı Chrome'a yeniden bağlanma talimatı verdiğinde Apple portalındaki gerçek yetkiler ve geliştirme/dağıtım profilleri kontrol edilir. Son yerel kontrol: sertifika var; ana uygulamanın gereken yetkilerini içeren geçerli yerel profil yok; yayın uzantısında bir uygun profil var. Bu, Apple başvurusunun sonucunu göstermez.
2. Uygun profil bulunduğunda ana uygulama ve uzantının gerçek imzası doğrulanır; aynı build iPhone 16 Pro'ya yüklenir. Bu çalışmada fiziksel telefona yükleme yapılmadı. Son doğrulanan telefon sürümü 0.1.0 (2) idi.
3. Önce doğrudan kabloyla CarPlay simgesi/sahnesi, video desteği bildirimi ve varsa gerçek harici ekran sahnesi kaydedilir. Debug ayarlarından uygun test başlatılır. Araçta sayacın değiştiği fiziksel olarak gözlenir; yalnız oynatıcı bayrağı kabul edilmez.
4. Aynı build ile markasız adaptörde test tekrarlanır. İki yolun sonucu ve raporu ayrı tutulur. Bir yol başarısızken diğeri başarılıysa fark mimari kararına girdi olur.
5. Kanıtlanan çıkış yolunda ReplayKit, kaynak uygulama geçişi, ses/görüntü senkronu, başlat/durdur ve uzun kullanım tamamlanır. Mevcut video hattı hâlâ 960×540 / 20 fps HLS'dir; uygulama sesini kodlamıyor. Nihai düşük gecikme ve ses mimarisi açık iştir.

Chrome ve Apple portalı işleri kullanıcının açık talimatıyla beklemededir. App Store yayını hedefi değişmedi; araç kabul testi, TestFlight ve App Review ayrı tamamlanma ölçütleridir.
