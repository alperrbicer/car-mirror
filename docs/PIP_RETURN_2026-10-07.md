# PiP dönüşünde tekrar yuvarlanan video köşeleri — 7 Ekim 2026

Kullanıcının cihazdaki akışı: küçük veya tam ekran film/dizi → arka plana geçiş → PiP penceresindeki uygulamaya dön düğmesi → video doğru yerleştikten sonra üst iki köşenin kısa süreliğine yuvarlanması. Canlı yayında gözlenmedi. Paylaşılan görüntülerde uygulamanın dışındaki sistem geçiş çerçevesine ek olarak video alanının üst köşeleri de yuvarlanıyor.

Önceki kod yalnızca `didStop` anında `cornerRadius`, `maskedCorners`, `mask` isimli üç animasyonu siliyordu. Bu yöntem, başka anahtarla eklenmiş/gruplanmış animasyonları ve bu temizlikten sonraki katman değişikliklerini kapsamıyordu. Cihazın gerçek katman zamanlaması kaydedilmediği için bunun tek neden olduğu iddia edilmez.

## Değişiklik

- Native AVPlayer ve VideoLAN örnek tamponu katmanları aynı `PlayerVideoClipping` yordamıyla korunur. Dikdörtgen kaynak geometrisi küçük ve tam ekranda aynıdır.
- PiP dönüşü tamamlandığında köşe yarıçapı ve maske durumu animasyonsuz düzeltilir. Ardından gelen değişiklikler KVO ile izlenir ve ana iş parçacığında anında düzeltilir. Sonradan eklenen renderer katmanları da taranır.
- Animasyonlar adlarına göre değil, değiştirdikleri özelliklere göre incelenir. Grupların içindeki köşe/maske animasyonları ayıklanırken diğer animasyonlar korunur.
- Açıkça eklenen animasyonlar KVO bildirimi üretmediğinden, dönüşten sonraki iki saniyede ekran yenilemeleriyle ek kontrol yapılır. Sürekli bir kare döngüsü çalıştırılmaz; sonrasında özellik gözlemleri ve layout kontrolü devam eder. İki saniye bir API garantisi değildir; çok daha geç eklenen, model özelliğini değiştirmeyen bir animasyon cihazda ayrıca izlenmelidir.
- Yeni PiP başlarken düzeltme durdurulur. Sistem PiP penceresinin kendi yuvarlak köşeleri değiştirilmez. Oynatıcı/decoder yeniden yaratılmaz, oynatma konumu ve duraklatma durumu korunur.
- Ekran görüntüsü engeli, cihazdaki sonucun paylaşılabilmesi için kapalı kalır.

Kullanılan kaynaklar: [Apple PiP içerik katmanı](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class/samplebufferdisplaylayer), [VideoLAN PiP delegate akışı](https://github.com/videolan/vlc/blob/master/modules/video_output/apple/VLCPictureInPictureController.m), [VideoLAN renderer katmanı](https://github.com/videolan/vlc/blob/master/modules/video_output/apple/VLCSampleBufferDisplay.m). Yalnızca açık UIKit, Core Animation ve AVFoundation API'leri kullanılır.

## Doğrulama

Uygulama ve test hedefleri iOS 26.5 / iPhone 17 Pro Max simülatörü için derlendi. Dokuz hedefli testin tamamı geçti: `build/pip-return-r2-20261007.xcresult` ve aynı adlı `.log`.

- İki yeni regresyon testi, gerçek `AVPlayerLayer` ve `AVSampleBufferDisplayLayer` katmanlarını bir UIKit penceresine bağlayarak küçük ve tam ekran boyutlarını kontrol eder. `didStop` sonrasındaki geç maske/radius yazımı, farklı anahtarlı gruplanmış animasyon, sonradan eklenen açık animasyon ve yeni PiP oturumunda sistem geometrisinin korunması doğrulandı. Gruptaki köşe animasyonu temizlenirken bağımsız opaklık animasyonunun korunduğu da kontrol edildi.
- Yedi mevcut kontrol geçti: gerçek MKV renderer'ın dönüşte temizlenmesi; decoder'ın küçük/tam ekran hostları arasında korunması; native içerik ve konumun korunması; arka plan/PiP hazır olma sırası; geç başlayan PiP yarışı; ekran görüntüsü izni ve isteğe bağlı koruma davranışı. Duraklatma durumu korunuyor.
- İlk çalıştırmada iki yeni test, pencereye bağlı olmayan katmanın animasyonunun UIKit tarafından bırakılması ve simülatörde sistem PiP controller oluşturulamaması nedeniyle başarısız oldu. Testler gerçek katmanları pencereye bağlayacak ve native delegate'in kullandığı aynı geometri yordamlarını çağıracak şekilde düzeltildi. Sonraki çalıştırmada dokuz test sıfır hatayla geçti.
- `git diff --check` temiz. Bu değişiklikte yeni kullanıcı metni eklenmedi.
- Gerçek MKV renderer'ın dönüşten sonraki sabit görüntüsü sonuç paketinden çıkarılıp incelendi: `build/pip-return-captures-20261007/958733A0-C1DB-4412-9135-A5B3D319565E.png`. Dört köşe dikdörtgen; bu tek görüntü cihazdaki geçişin her karesini kanıtlamaz.

Simülatör sistem PiP dönüş animasyonunu sağlamadığından bu testler cihazdaki iOS animasyonunu taklit etmiş sayılmaz. Fiziksel iPhone'a kurulum bu çalıştırmada yapılmadı; kullanıcının tarif ettiği gerçek dönüş akışındaki görsel sonuç ayrıca doğrulanmalıdır.

## Son canlı yayın örneği sonrasında ek düzeltme

Kullanıcı aynı geçici yuvarlanmayı canlı yayının küçük oynatıcısında da gösterdi. Önceki yaklaşım içerik türüne özgü bir sorun olduğunu kanıtlamıyordu. Kodda iki kapsam açığı bulundu: yalnızca AVPlayer/SampleBuffer türündeki katmanlar temizleniyor, sıradan saran/iç renderer katmanları atlanıyordu; ayrıca uygulama henüz `inactive` durumundayken dönüşteki ilk görünür karelerde temizlik yapılmıyordu.

- Temizlik uygulamanın sahip olduğu video ağacında video katmanına giden sarmalayıcılara ve video katmanının altındaki renderer katmanlarına genişletildi. Altyazı gibi video dışı kardeş görünümlerin maskeleri korunur. Pencere veya uygulamanın tüm UIKit ağacı değiştirilmez.
- Alt katmanların eklenmesi izlenerek sonradan oluşturulan renderer çocukları da düzeltilir. Yeni PiP oturumu başlarken izleme yine durdurulur.
- Uygulamanın `willEnterForeground` olayı ve native PiP'nin `willStop`/arayüz geri yükleme aşaması, `didStop` beklenmeden video geometrisini hazırlar. Dönüş hazırlığında `active` olma şartı kaldırıldı. Oynatıcı ve decoder yeniden yaratılmaz.
- `build/continue-watching-r3-20261007.xcresult` içindeki on PiP/oynatıcı kontrolü test bazında geçti. İki yeni kontrol, eski kodun atladığı sıradan parent/child katmanları, sonradan bağlanan çocukları, bağımsız altyazı geometrisini ve PiP henüz aktifken ön plan hazırlığının `didStop` öncesi gerçekleşmesini doğrular. Aynı paketin medya sunucusu/arayüz nedeniyle başarısız başka testleri PiP sonucu olarak sayılmaz.
- Native ve VideoLAN aynı geometri politikasını kullanır. Canlı/VOD ayrımından çok kullanılan renderer ve geri dönüş sırası önemlidir; cihazdaki tek sebebin bu olduğu fiziksel gözlem olmadan iddia edilmez.

Apple akışı: [PiP kapanmadan önce delegate bildirimi](https://developer.apple.com/documentation/avkit/avpictureinpicturecontrollerdelegate/pictureinpicturecontrollerwillstoppictureinpicture%28_%3A%29). [VideoLAN'ın public PiP bildirimleri](https://github.com/videolan/vlc/blob/master/modules/video_output/apple/VLCPictureInPictureController.m) uygulamaya didStart/didStop durumlarını iletir; bu nedenle VideoLAN dönüş hazırlığı uygulamanın ön plan olayında da yapılır.

Kullanıcı cihazı bağlayıp kilidini açtı. Aynı uygulama kimliğiyle imzalı Debug derleme kuruldu. Cihaz test girişi yalnız DEBUG'dır, kaynakları/tercihleri temizlemez ve yerel dosyayı izleme geçmişine yazmaz. Cihazın uygulama önbelleğine yalnızca özgün MP4/MKV örnekleri kopyalandı.

## Fiziksel bulgu ve son geometri düzenlemesi

- İlk cihaz koşusu otomasyon modu zaman aşımında test başlatamadı. Kullanıcı UI Automation'ı açtıktan sonra koşular başladı. Sonraki testlerde sistem PiP kontrolleri sorgulanırken gizleniyordu; gözlenen PiP penceresinde kontrolleri yeniden gösterip “Tam ekrana dön” düğmesini seçen test düzeltildi.
- `build/physical-pip-return-r5-20261007.xcresult`: MP4/MKV × küçük/tam ekran olmak üzere dört test geçti. Her test hem uygulamayı açarak hem PiP'nin dönüş düğmesiyle dönüşü kontrol eder. Oynatıcı boyutunun korunması ve son sabit dikdörtgen görüntü doğrulandı. Bu sonuç ara karelerin kusursuz olduğu anlamına gelmez.
- `build/physical-pip-visual-r6-20261007.xcresult`: iki temsilci koşu ekran kaydıyla tekrar geçti. Kayıtta video, siyah bantları içeren yüzeyden gerçek görüntü alanına yerleşirken kısa bir köşe değişimi hâlâ gözlendi. `UIView.performWithoutAnimation` ile PiP durdurmayı sarmalamak bunu gidermedi; etkisiz deneme kodu kaldırıldı.
- Son düzenleme, hem AVPlayerLayer hem VideoLAN drawable'ını **sığdır modunda gerçek görüntü oranına göre merkezler**. Siyah bantlar dış hostta kalır; PiP kaynak yüzeyinin içine alınmaz. Doldur modunda yüzey yine tüm hostu kaplar. Native görünüm güncellenirken, VideoLAN video boyutu hazır olduğunda ve host değiştiğinde geometri yeniden hesaplanır. Decoder ve video konumu korunur. Bunun cihazdaki tek neden olduğu iddia edilmez.
- `build/pip-geometry-regression-r7-20261007.xcresult`: son kodla dokuz yerel kontrol geçti, **TEST SUCCEEDED**. Gerçek MP4/MKV görüntüsünde kaynak yüzeyinin kendi içinde siyah bant bırakmaması, doldurmaya geçip geri dönerken çalışan decoder'ın korunması, görünür MKV çıktısı, host sahipliği ve önceki PiP maske/ön plan kontrolleri doğrulandı.
- Son geometriyle başlayan `physical-pip-return-r7` koşusunda üç senaryo geçti; native küçük ekran dönüşünde ölçülen alan 362×203,67'den 710×399,33'e değiştiği için boyut kontrolü başarısız oldu. Bu değişimin nedeni doğrulanmadı; koşu başarılı sayılmaz. Kullanıcı fiziksel cihaz testlerini kendisinin yapacağını belirtti. Yeni cihaz testi veya cihaz işlemi başlatılmadı; son geometri değişikliğinin görsel kabulü kullanıcıya bırakıldı.

Güncel durumda PiP'nin sistem penceresinin şeklini veya iOS'un tüm dönüş animasyonunu kaldırdığımız iddia edilmez. [Apple'ın stopPictureInPicture API'si](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/stoppictureinpicture%28%29) animasyon parametresi sunmaz; yerel SDK başlığı da `didStop` bildiriminin durdurma animasyonundan sonra geldiğini belirtir. Uygulamanın kaynak geometrisi ve eski maskeleri düzeltilmiştir; son cihazdaki kısa köşe sıçraması kullanıcı tarafından yeniden kontrol edilmelidir. Ekran yakalama izni açık kalır.

## Dört ekran görüntüsü sonrası dönüş sırası düzeltmesi

Yeni örnek küçük oynatıcı → otomatik PiP → PiP'nin uygulamaya dön düğmesi → geçici tam ekran → üst köşeleri oval video → dikdörtgen video sırasını gösteriyor. Önceki bölümdeki test sonuçları bu düzenlemenin doğrulaması değildir.

Kod incelemesinde iki eksik görüldü: kullanılan VideoLAN PiP arayüzü uygulamaya yalnız başlangıç/bitiş durumunu iletiyor; arayüzü geri çağıran kod `didStop` sonrasında çalışıyordu. Ayrıca uygulamanın aktif olması, PiP'nin kendi dönüşü devam ederken ikinci bir `stopPictureInPicture` isteği oluşturabiliyordu. Ön planda başlayan maske temizliği de henüz AVKit'e ait olan köşe animasyonlarına müdahale ediyordu.

- VideoLAN'ın mevcut `AVSampleBufferDisplayLayer` katmanına uygulamanın yönettiği tek bir `AVPictureInPictureController` bağlandı. Drawable, VideoLAN'ın ikinci bir PiP controller oluşturmasını sağlayan protokolü artık uygulamıyor. Decoder ve oynatma oturumu korunuyor; oynat/duraklat, zaman aralığı ve atlama işlemleri aynı motora iletiliyor.
- Native ve VideoLAN yolları, [AVKit'in arayüzü PiP kapanmadan geri yükleme bildiriminde](https://developer.apple.com/documentation/avkit/avpictureinpicturecontrollerdelegate/pictureinpicturecontroller%28_%3Arestoreuserinterfaceforpictureinpicturestopwithcompletionhandler%3A%29) ortak dönüş yordamını kullanıyor. Başarı bildirimi, kaynak görünüm pencereye bağlanıp UIKit yerleşimi tamamlandıktan sonra veriliyor. Küçük/tam ekran tercihi değiştirilmeden mevcut oynatıcı kullanılıyor.
- PiP düğmesinden dönüş ile uygulama ikonundan dönüş ayrıldı. Sistemin başlattığı dönüş, aktif olma olayı tarafından tekrar durdurulmuyor. Yeni bir oynatma oturumuna ait olmayan gecikmiş yerleşim sonuçları reddediliyor.
- Ön plan ve `willStop` aşamaları yalnızca yerleşimi hazırlıyor. Radius/maske temizliği artık `didStop` sonrasında yapılıyor; devam eden sistem animasyonunun maskesi sıfırlanıp yeniden uygulanmıyor. Video hostları kendi dikdörtgen sınırlarının dışını da kırpıyor.
- Oynatıcı ekranının yeniden açılması gerekirse ek SwiftUI sunum animasyonu kapatılıyor. Eşzamanlı arayüz geri yükleme isteklerinin completion'ları kaybedilmiyor.

Bu değişiklikte cihaz/simülatör açılmadı, kurulum yapılmadı ve test çalıştırılmadı. Uygulama hedefinin 49 Swift kaynak dosyası mevcut SDK ve önceden derlenmiş bağımlılıklarla `swiftc -typecheck` kontrolünden geçti (`build/pip-return-typecheck-20261007.log`); bu bir tam Xcode derleme/link veya çalışma zamanı testi değildir. Mevcut PiP regresyon testleri yeni tamamlanma sırasına uyarlandı ancak çalıştırılmadı. Dört görüntüdeki ara karelerin görsel kabulü kullanıcının aynı cihaz akışındaki kontrolüne bırakıldı.

## Canlı tam ekranı referans alan dört geçiş

Kullanıcının son karşılaştırmasında canlı yayının tam ekran dönüşü düzgün; canlı yayının küçük oynatıcısı ile dizi/filmin iki boyutu hatalı. Canlı/tam ekran için ayrı bir köşe animasyonu yok: native HLS ve native VOD aynı AVPlayer yolunu, MKV içerik VideoLAN yolunu kullanıyor. Her ikisi de `PlayerVideoReturnLayout` üzerinden dönüyor. Ortak dönüşteki eksik, bir UIKit transaction tamamlanınca gezinme ve güvenli alan yerleşiminin de sabitlendiğinin varsayılmasıydı.

- İki motorda da dönüş hedefi artık görünür pencereye bağlı olmalı ve üç ardışık ekran yenilemesinde aynı konum/boyutta kalmalı. Üst görünümlerin devam eden yerleşim animasyonları da beklenir. Bu, canlı tam ekrandaki sabit hedef koşulunu diğer boyutlara uygular; küçük oynatıcıyı geçici tam ekrana çıkarmaz.
- Native yolda yalnız dış host değil, PiP'nin gerçek `AVPlayerLayer` dikdörtgeni de kontrol edilir. Değişmeyen video çerçevesi tekrar yazılmaz. VideoLAN'ın mevcut drawable/decoder sahipliği korunur.
- Henüz pencereye bağlanmamış görünümün bağlanması beklenir. Gizli bir üst görünümün içindeki video dönüşe hazır sayılmaz. Hazırlık bir saniye içinde tamamlanmazsa başarısızlık bir kez bildirilir; görünmeyen hedef için başarı verilmez.
- Hazırlık AVKit'in video katmanındaki geçiş animasyonunu veya köşelerini değiştirmez. Önceki `didStop` sonrası maske temizliği korunur. Bu değişiklikte fiziksel cihaza kurulum yapılmadı; kullanıcının üç hatalı senaryosundaki görsel sonuç henüz cihazda doğrulanmadı.

Son kodla uygulama ve test hedefleri derlendi; iOS 26.5 / iPhone 17 Pro Max simülatöründe sekiz odaklı testin tamamı geçti (`TEST SUCCEEDED`). Yeni kontroller iki motorda küçük/tam ekran dönüşünün hareket eden üst görünümü beklediğini, geç pencereye bağlanmayı ve gizli hedefin reddedilmesini doğruluyor. Mevcut kontroller de ikinci PiP durdurma isteğini, geç başlangıcı, duraklatma/decoder durumunu, görüntü oranını ve dönüş sonrası maske temizliğini kapsıyor. Bunlar fiziksel cihazdaki sistem animasyonunun görsel kanıtı değildir. Kayıtlar: `build/pip-transition-layout-20261007.log` ve `build/pip-transition-layout-20261007.xcresult`.
