# Yenileme, son izlenen ve medya dili seçenekleri — 7 Ekim 2026

- Kaynak menüsündeki “Bilgileri yenile” seçimi, karttaki göstergenin yanında ortada belirgin bir spinner açar. İşlem hızlı sonuçlansa bile 1,5 saniye gösterilir; istek uzun sürerse gerçek işlem tamamlanana kadar kalır. Başarı mesajı uydurulmaz; önceki hesap bilgisi korunur.
- Son izlenen çevrimiçi video uygulama yeniden açıldığında alttaki “İzlemeye devam et” alanından açılır. Soğuk açılışta video veya “Şimdi oynatılıyor” durumu otomatik başlatılmaz. Film/dizi kaldığı konuma, canlı yayın güncel yayına döner. Bitmiş içerik baştan açılır.
- Tek kayıt içerik adı, yayın adresi, kaynak kimliği ve oynatma konumunu içerir; URL giriş bilgisi taşıyabileceğinden bu cihaza bağlı Keychain alanında tutulur. Oynatma sırasında en geç beş saniyede bir, duraklatmada, uygulama arka plana geçerken ve durdurmada güncellenir. Kaynağı düzenlemek/silmek veya tüm kaynakları silmek ilgili kaydı temizler. Silinen kaydın açık eski oturumdan tekrar yazılması engellenir. Başlamayan içerik önceki başarılı kaydı değiştirmez. Geçici kişisel medya dosyaları bu kayda alınmaz.
- Küçük ve tam ekran oynatıcının üstündeki “Ses ve altyazı” düğmesi mevcut medya parçalarını listeler. Birden çok ses parçasında ses dili/dublaj seçilir; altyazı varsa dili seçilir ve motor izin verdiğinde kapatılır. Seçim mevcut oturumda yapılır, video yeniden açılmaz. Parça sunmayan içerikte düğme gösterilmez.
- Native oynatıcı AVFoundation medya seçim gruplarını; VideoLAN oynatıcı VLCKit 4 parça seçimini kullanır. Bu özellik yayının sunduğu altyazıları seçer; yeni altyazı/dublaj üretmez. Google Cast alıcısında parça seçimi bu değişikliğe dahil değildir. AirPlay/TV ve fiziksel cihaz kabulü ayrıca gerekir.
- Yeni beş metin 22 dile çevrildi. Yerel gizlilik sitesi ve dağıtım ZIP’i son izlenen kaydıyla güncellendi; siteye yayın yapılmadı.

API kaynakları: [Apple medya seçim grupları](https://developer.apple.com/documentation/avfoundation/avasset/loadmediaselectiongroup%28for%3Acompletionhandler%3A%29), [VideoLAN VLCKit](https://videolan.videolan.me/VLCKit/interface_v_l_c_media_player.html). Kullanılan VLCKit 4 parça API’si projedeki kurulu SDK başlıklarından ayrıca kontrol edildi.

## Doğrulama

Testler özgün demo videosundan oluşturulmuş iki ses ve iki altyazı parçalı MP4/MKV kullanır; gerçek sağlayıcı hesabı içermez.

- Uygulama ve test hedefleri iOS 26.5 / iPhone 17 Pro Max simülatöründe derlendi.
- Dört yeni uygulama testi geçti: Keychain kaydının yeniden okunması; canlı/bitmiş/geçici dosya davranışı; gerçek oynatıcıda konumdan devam ve kaynak silindiğinde kayıt temizliği; AVFoundation ve VLCKit üzerinde ses/altyazı seçimi. Parça değiştirdikten sonra aynı oynatıcı oturumunda videonun ilerlediği doğrulandı. Sonuç: `build/playback-options-unit-r5-20261007.xcresult` ve aynı adlı `.log`.
- Mevcut iki ileri/geri sarma kontrolü MP4 ve MKV üzerinde geçti. Sonuç: `build/playback-options-ui-20261007.log` içindeki `testPlayingNativeVideoContinuesAfterSeeking` ve `testPlayingCompatibilityVideoContinuesAfterSeeking`.
- İki arayüz testi son çalıştırmada geçti: hızlı cevap veren kaynakta yenilemenin tamamlanması; küçük/tam ekranda ses ve altyazı seçimi; uygulamayı sonlandırıp tekrar açtıktan sonra son izlenen alanının görünmesi ve sıfırdan farklı konuma devam edilmesi. Soğuk açılışta otomatik oynatma yapılmadığı da doğrulandı. Sonuç: `build/playback-options-ui-r2-20261007.xcresult` ve aynı adlı `.log`.
- Yenileme göstergesinin gerçek 1,5 saniyelik görünümü test sırasında dışarıdan simülatör ekran görüntüsüyle yakalandı ve incelendi. XCTest dokunmadan sonra uygulamanın durulmasını beklediği için kısa göstergenin görünürlüğü yalnızca `waitForExistence` ile ölçülmedi. İlk arayüz çalıştırmasındaki bu zamanlama kontrolü ve iki “Kapat” düğmesini eşleştiren belirsiz test sorgusu düzeltildi; ürün göstergesinin süresi test için uzatılmadı.
- MKV'nin aynı anda açtığı HTTP aralık isteklerini desteklemek için yalnızca yerel test sunucusu eşzamanlı istek kabul edecek şekilde düzeltildi. Testler bu sunucuyla tekrar geçti.
- 22 dil / 285 anahtar / 6.270 çeviri değeri kontrolü geçti; eksik anahtar veya çeviri hatası yok. Sonuç: `build/playback-options-localization-20261007.log`.

İncelenen ekran görüntüleri `build/playback-options-20261007/` altında: `mirivo-source-refresh-visible.png`, `mirivo-player-audio-and-subtitles.png`, `mirivo-player-fullscreen-subtitles-off.png`, `mirivo-last-watched-after-relaunch.png`, `mirivo-last-watched-resumed.png`.

Test medyası gerektiğinde `scripts/generate_playback_options_fixture.py` ile üretilebilir (`imageio-ffmpeg` gerekir); `scripts/capture_store_screenshots.py` bu dosyaları yerel olarak sunar. Medya uygulama paketine eklenmez.

Fiziksel iPhone'a kurulum, gerçek IPTV sağlayıcısının dil parçaları ve AirPlay/TV kontrolü bu çalıştırmada yapılmadı. Önceki PiP köşe geçişi konusu bu testlerle kapanmış sayılmaz; kullanıcının örnek gönderebilmesi için ekran görüntüsü engeli kapalı kalır.
