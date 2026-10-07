# Mirivo oynatıcı düzeltmeleri — 7 Ekim 2026

- Araç modu ücretsiz kullanıcıya açıktır ve telefon oynatımıyla aynı günlük 2 saatlik bütçeyi kullanır. Ayrı bir 2 saat verilmez. Bütçe bitince mevcut oynatmayı durduran mekanizma korunur. Pro ekranında araç modu ücretli ayrıcalık olarak listelenmez.
- Pro sayfasının sağ üstünde 44 pt kapatma butonu vardır; hem açılır sayfada hem gezinme içinde çalışır.
- Video üzerindeki sol/sağ çift dokunma, aranabilir içerikte 10 saniye geri/ileri gider. Canlı yayınlarda geçersiz sarma kontrolleri gösterilmez.
- Küçük oynatıcıda alt sıra araç modu, PiP ve oynatma listesidir; tam ekran düğmesi üst sağdadır. Küçük görüntüde üç nokta menüsü yoktur. Tam ekranın alt sırasında araç modu, tam ekran ve oynatma listesi bulunur; PiP, görüntüyü sığdır/doldur, kilit ve durdur seçenekleri tam ekran menüsündedir.
- İki parmakla açma görüntüyü doldurur; kapatma sığdırır. Bu hareket hem AVPlayer hem VideoLAN içeriklerinde aynı katmanda işlenir.
- Tam ekranda aşağı doğru kaydırma normal oynatıcıya döner. Kilit açıkken hareketler devre dışıdır. Normal boyutta kaydırma sayfa gezinmesini engellemez.
- Normal/tam ekran geçişi aynı video yüzeyinin boyutunu değiştirir; ikinci oynatıcı sunumu ve siyah geçiş yer tutucusu kaldırılmıştır. Hareketi azalt sistem tercihi gözetilir.
- AVKit'in hazır kontrol katmanı yerine AVPlayerLayer ve Mirivo kontrolleri kullanılır. Böylece iki kontrol grubu üst üste binmez. Tam ekran kontrolleri pencerenin güvenli alanını korur. Oynatıcı açıkken küçük oynatma çubuğu gizlenir.
- Yerel video oynatımı arka plana geçerken PiP başlatmayı dener; video katmanı henüz hazır değilse hazır olmasını bekler. Açık PiP yeniden başlatılmaz, duraklatılmış durum korunur. Ses, Cast ve harici ekran oynatımı için yerel PiP başlatılmaz. Kaynak video ve delegesi PiP boyunca tutulur. PiP dönüşünde açılan oynatıcı da tam ekranı kullanabilir.

## Takip düzeltmeleri

- İleri/geri sarma bildirimindeki uzun yazılı kapsül kaldırıldı. Dokunulan tarafta küçük `−10` / `+10`, yön simgesi ve ince mint halka gösterilir; yerleşim merkez kontrollerinin dışındaki boşluğa göre daralır. Bildirim kısa süre sonra saydamlaşarak kaybolur, tekrarlanan dokunuş halkayı yeniden oynatır. Yön değişince bildirim ekranda karşı tarafa uçmaz. Hareketi azalt ayarında halka devre dışıdır. Kanal, tam ekran, kilit veya sayfa değişiminde eski bildirim temizlenir. Merkez düğmesinin yeşil dolgusu kaldırılmıştır; beyaz simge ve %25 siyah şeffaf zemin kullanılır.
- İkinci kaynak eklerken açılan Pro sayfasında kapatma düğmesinin tek sahibi `ProView` olur. Kaynak ekranının eklediği ikinci çarpı kaldırılmıştır. Ücretsiz bir kaynak sınırı korunur.
- Tam ekran seçenekleri sunumu açıkça izlenen bir popover kullanır. Açıkken kontroller gizlenmez; 30 saniye sonra popover kapanır. Seçim yapmak veya dışına dokunmak daha erken kapatır. VoiceOver açıkken süreyle kapatma uygulanmaz.
- Uygulama yeniden aktif olduğunda PiP durdurulur ve mevcut oynatıcıya dönülür. Oynatıcı henüz görünmüyorsa önce görünür olması beklenir. Video, konum, duraklatma ve açık olan tam ekran görünümü yeniden oluşturulmaz. PiP başlama işlemi dönüşten sonra tamamlanırsa o oturum da kapatılır; henüz başlamamış arka plan istekleri iptal edilir.
- Uygulamadaki önizleme, küçük oynatıcı ve tam ekran video yüzeyleri sabit köşeli kullanılır. Boyut/gezinme değişimlerinde ek köşe yarıçapı animasyonu yoktur. VideoLAN yüzeyi boyutlandırılırken örtük katman animasyonları kapatılır; tamamlanmış PiP dönüşündeki eski renderer maskesi temizlenir. iOS'un PiP penceresinin dış şekli ve sistem geçiş animasyonu uygulama tarafından özelleştirilemez; fiziksel cihazda tamamen sabit kaldığı iddia edilmez.
- Küçük oynatıcıdaki ekran görüntüsü talebi tam karşılanmamıştır: aşağıdaki koruma yalnızca VideoLAN sample-buffer video katmanlarını kapsar. Standart AVPlayerLayer ve arayüz ekran görüntüsünde kalabilir.

## Ekran görüntüsü sınırı

Kullanıcının PiP köşe geçişinden örnek paylaşabilmesi için video yakalama kısıtlaması geçici olarak kapatıldı (`captureProtectionEnabled = false`). Bu değişiklik yeni derlemeyle geçerlidir; hâlihazırda kurulu uygulamayı uzaktan değiştirmez. VideoLAN katmanları, sonradan eklenen renderer ve PiP dönüşü yakalamaya izin verir. Örnekler incelendikten sonra koruma yeniden değerlendirilecektir.

Koruma açıldığında AVSampleBufferDisplayLayer için Apple'ın `preventsCapture` özelliği kullanılır; tüm uygulamada ekran görüntüsü engelleme desteği olduğu iddia edilmez.

Bu, tüm uygulamada ekran görüntüsünü engellemez. UIKit/SwiftUI arayüzü ve korunmasız AVPlayerLayer içeriği hâlâ yakalanabilir. Ekran görüntüsü bildirimi çekimden sonra gelir; çekimi iptal etmek için kullanılmaz. Özel UIKit sınıflarına veya parola alanı katman hilelerine dayanılmaz.

Kaynaklar: [Apple preventsCapture](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/preventscapture), [Apple ekran görüntüsü bildirimi](https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification).

## İlk düzenlemelerin doğrulaması

- Çekirdek: 46 test başarılı; günlük bütçe, gece yarısı yenilemesi ve içerik sınıflandırması dahil.
- Oynatıcı/TV: 30 test çalıştı; 27 başarılı, sağlayıcı bilgisi gerektiren 3 test atlandı.
- Son odaklı oynatıcı turu: 4/4 başarılı ve `TEST SUCCEEDED`; standart/MKV sarma sonrası oynatma, geç hazır olan PiP ve katman koruması kontrol edildi.
- Son oynatıcı arayüz testi: başarılı ve `TEST SUCCEEDED`; video üzerindeki üç buton, çift dokunma, ücretsiz araç modu, pinch, yatay/dikey güvenli alan ve aşağı kaydırarak çıkış kontrol edildi.
- Pro çarpısı: arayüz testinde sayfayı kapatıp ayarlara döndüğü doğrulandı.
- İlk geniş oynatıcı/TV turu testlerini tamamladıktan sonra Xcode oturum kapanışında bekledi ve sonlandırıldı; bu turun sonuçları günlükte bulunur. Son odaklı oynatıcı ve oynatıcı arayüz turları normal tamamlandı.
- `git diff --check` temiz.

Kayıtlar: `build/player-core-20261007.log`, `build/player-fixes-r2-20261007.log`, `build/player-final-20261007.log`, `build/player-ui-r3-20261007.log`, `build/player-gestures-final-20261007.log`.

Görseller: [normal oynatıcı](../build/player-polish-20261007/mirivo-player-inline-custom-controls.png), [araç modu](../build/player-polish-20261007/mirivo-player-free-vehicle-mode.png), [yatay tam ekran](../build/player-polish-20261007/mirivo-player-fullscreen-landscape-controls.png), [tam ekrandan dönüş](../build/player-polish-20261007/mirivo-player-inline-after-fullscreen.png).

## Takip doğrulaması

- Oynatıcı: 5/5 test başarılı ve `TEST SUCCEEDED`. Arka plandan dönüşte oynatma/duraklatma durumu, gecikmiş PiP başlangıcı, iptal edilen eski istekler, VideoLAN maskesi/katman koruması ve native videonun yatay/dikey yerleşimi kontrol edildi. PiP yaşam döngüsü testleri denetleyici taklidi kullanır; gerçek sistem penceresinin animasyonu için cihaz kanıtı değildir.
- Arayüz: temiz iOS 26.5 iPhone 17 Pro Max simülatöründe 3/3 test başarılı ve `TEST SUCCEEDED`. Yeni düğme yerleşimi, çift dokunma, ücretsiz araç modu, pinch, 30 saniyelik menü kapanışı, ardından yatay/dikey dönüş ve aşağı kaydırarak çıkış doğrulandı. Pro ekranı hem ayarlardan hem ikinci kaynak sınırından tek çarpıyla kapandı.
- Birleşik test oturumlarında önceki simülatörün yönü değişmedi; aynı kodun arayüz testleri temiz simülatörde ayrı çalıştırıldı ve geçti. Dönüş testinin temizliği desteklenen tüm yönleri geri yükler. Yön takılmasının fiziksel cihazda meydana geldiği iddia edilmez.
- Sarma bildirimi ve şeffaf merkez düğmesi son ekran görüntülerinde incelendi. `git diff --check` temiz.

Son kayıtlar: `build/player-followup-unit-20261007.log`, `build/player-followup-unit-20261007.xcresult`, `build/player-followup-ui-clean-20261007.log`, `build/player-followup-ui-clean-20261007.xcresult`.

Güncel görseller: [küçük oynatıcı](../build/player-followup-20261007/mirivo-player-inline-custom-controls.png), [tam ekran menüsü](../build/player-followup-20261007/mirivo-player-fullscreen-options.png), [yatay tam ekran](../build/player-followup-20261007/mirivo-player-fullscreen-landscape-controls.png), [tek Pro çarpısı](../build/player-followup-20261007/mirivo-source-limit-pro-single-close.png).

- Kullanıcı fiziksel iPhone'da küçük/tam ekran oynatımından otomatik PiP açılışının iyi çalıştığını bildirdi. Bu takip değişikliklerinden sonraki uygulamaya dönüş/köşe geçişleri, gerçek ekran görüntüsünün video koruması ve AirPlay/yansıtma davranışı henüz cihazda doğrulanmadı. Simülatör sonuçları bunların kanıtı sayılmaz.

## PiP köşeleri için örnek toplama

Kullanıcı köşe geçişinin fiziksel cihazda sürdüğünü bildirdi. Sabit dikdörtgen kaynak ve tamamlanmış dönüşte renderer maskesinin temizlenmesi sorunu cihazda çözülmüş saymak için yeterli değildir. Yeni bir görsel düzeltme doğrulanmadan tamamlandı denmez. Geçici yakalama izni hem önceden korunmuş hem sonradan eklenen video katmanlarında kontrol edildi; koruma yeniden açılabilmektedir.

## Sarma geri bildirimi tasarımının doğrulaması

- Uzun metin yerine yön simgesi, `−10` / `+10` ve kısa halka animasyonu kullanılır. Bildirim 900 ms sonra sönmeye başlar; yeni dokunuş süreyi ve halkayı yeniler. Video konumunu değiştiren mevcut 10 saniyelik sarma davranışı korunur.
- Temiz iOS 26.5 iPhone 17 Pro Max simülatöründe `testPlayerModesGesturesAndControlLayout` başarılı (`TEST SUCCEEDED`, 1 test, 0 hata). Küçük oynatıcıda ileri/geri çift dokunma, araç modu, pinch, seçenek menüsü, yatay/dikey tam ekran ve aşağı kaydırarak dönüş kontrol edildi. Uygulama ve test hedefleri aynı çalıştırmada derlendi.
- Küçük oynatıcıda iki yön ve yatay tam ekranda ileri sarma gerçek ekran görüntüleriyle incelendi. Önceki simülatördeki ilk denemede yalnızca yön değiştirme kontrolleri başarısızdı; test değiştirilmeden temiz simülatörde geçti. Fiziksel cihazda bu tasarım henüz kontrol edilmedi.
- Yerelleştirme denetimi: 22 dil, 280 anahtar, 6160 değer, hata yok. `git diff --check` temiz.

Kayıtlar: `build/seek-feedback-ui-20261007.log`, `build/seek-feedback-ui-clean-20261007.log`, `build/seek-feedback-ui-clean-20261007.xcresult`, `build/seek-feedback-localization-20261007.log`.

Görseller: [ileri sarma](../build/seek-feedback-20261007/mirivo-player-seek-forward-inline.png), [geri sarma](../build/seek-feedback-clean-20261007/mirivo-player-seek-backward-inline.png), [yatay tam ekran](../build/seek-feedback-clean-20261007/mirivo-player-seek-forward-landscape.png).
