# CarPlay doğrulaması — 5 Kasım 2026

## CarPlay Simulator ve bağlı iPhone

Testte Mac üzerindeki CarPlay Simulator ve iOS 27.0 (24A437) yüklü iPhone 16 Pro kullanıldı. Aşağıdaki ekran davranışlarını kullanıcı gözlemledi. Seçim işleyicisinin çalışıp çalışmadığı ayrıca uygulama günlüklerinden kontrol edildi.

| Derleme | CarPlay yapılandırması | Simülatörde gözlenen sonuç |
| --- | --- | --- |
| 92 | Yalnız Audio, satır seçimden önce video istiyor | Satır seçili kaldı. İşleyiciye seçim ulaşmadı. |
| 93 | 92 ile aynı çalıştırılabilir dosya, tanı amacıyla imzaya Video eklendi | Seçim ulaştı ve görüntü otomatik açıldı. |
| 94 | Yalnız Audio, satır ses olarak seçiliyor ve oynatıcı video hazırlıyor | Oynatma ekranı açıldı. Görüntünün otomatik açılmadığı ve 4. saniyede duraksama olduğu bildirildi. |
| 95 | Yalnız Audio, seçimden önce video tercihi ve ek oynatıcı oturumu | Satır yine takıldı. Bu deneme kaldırıldı. |
| 96 | Yalnız Audio, video tercihi seçim işleyicisine girildikten sonra bildiriliyor | Kullanıcı yayının akıcı başladığını, oynatma ekranındaki düğmeye dokununca görüntünün açıldığını doğruladı. |

Kaynaklar ve Favoriler aynı seçim sırasını kullanıyor. Başarılı bir seçim içeriği hazırlıyor, oynatma ekranını açıyor ve oynatmayı başlatıyor. Listeye dönüldüğünde satır tekrar seçilebiliyor. Radyo ve yalnız ses destekleyen araçlar ses kipini kullanıyor. Park hâlinde görüntüyü açma kararı CarPlay’e ait. Uygulama sistem düğmesine basılmasını taklit etmiyor. [Apple’ın video sunumu açıklaması](https://developer.apple.com/forums/thread/831710)

Apple’ın 1.0 (41) için 21 Ekim 2026 tarihli inceleme mesajı, Audio ve Video yetkilerinin birlikte kullanılması nedeniyle Video’nun kaldırılmasını istiyor. Uygulama imzasında yalnız CarPlay Audio kullanılmalı. Aynı mesajdaki 5.2.5 maddesi App Store alt başlığında AirPlay adının kullanımına ilişkin ayrı bir bulgu.

## Oynatma ve gezinme

- Eski 4 saniyelik ilk parçadan sonraki 16 saniyelik parçayı hazırlamak, kullanıcının seçtiği yayında 8,48 saniye sürdü. Eşit 6 saniyelik parçalar ve VLC’nin varsayılan çözücü seçimiyle aynı cihazda sonraki üç parça 3,81, 3,91 ve 4,15 saniyede hazırdı. Önbellekteki parçanın okunması da bir sonraki parçanın hazırlanmasını tetikliyor.
- Kısa ve sessiz MKV örneğinde dönüştürücü, her parçanın zaman damgalarını sıfırdan başlatıyordu. Kırpma kodu hem parça saatini hem de kaynak saatini tanıyor ve oynatıcıya listede belirtilen süreyi gönderiyor. Ses izi içermeyen bu tür videolarda AVPlayer kendi ileri tamponunu seçiyor. Ses içeren yayınlarda önceki tampon ayarı kullanılıyor. Otomatik oynatma testi, ileri sarmadan veya yeniden Oynat’a basmadan üçüncü parçadan bir video karesi alıyor.
- Kaynaklar ve dizi favorileri önbellekten açılabiliyor. Ana sayfaya veya Favoriler’e geçiş bekleyen yüklemeyi iptal ediyor. Eski yanıt yeni satırın seçimini tamamlayamıyor.
- Favoriler ekranı yeniden kullanılıyor. Oynatma durumu değiştiğinde favori satırları yeniden oluşturulmuyor. Kullanılmayan oynatma ekranı çağrısı ve seçim sorununu çözmeyen tanı kodu kaldırıldı.

## Testleri tekrarlama

Simülatörde çok sesli örnek için önce `python3 scripts/generate_playback_options_fixture.py`, ardından `python3 scripts/capture_store_screenshots.py` kullanılır. Uygulama testleri `VehiclePlaybackTests`, `PerformanceRegressionTests`, `PersonalMediaIntegrationTests` ve `PlayerTests` içindeki CarPlay denetimleridir.

Fiziksel cihazdaki örnek tampon testi, `options.mkv` dosyasını uygulamanın `Library/Caches/mirivo-carplay-prefetch-test.mkv` konumundan okur. Test çalıştırıcısında `MIRIVO_TEST_VOD_FILE=1` kullanılır. Test bitince dosya temizlenir. `MIRIVO_TEST_SAVED_VOD=1`, cihazda en son seçilen videoyla tampon testini etkinleştirir. Bu test kaynak adresini yazdırmaz ve oynatma geçmişini değiştirmez.

Bu çalışmanın günlükleri Git tarafından izlenmeyen `build/carplay-e2e/` dizinindedir.
