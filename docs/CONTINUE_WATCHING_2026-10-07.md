# Birden fazla film ve diziye devam etme — 7 Ekim 2026

Kaynaklar ekranındaki yinelenen üst “Şimdi oynatılıyor” kartı yerine “İzlemeye devam et” bölümü eklendi. Gerçek aktif oynatma alttaki oynatıcı çubuğunda kalır; aynı içerik bu bölümde ikinci kez gösterilmez. Soğuk açılışta hiçbir içerik otomatik başlatılmaz.

## Kalabalığı önleyen davranış

- Ana sayfada en son üç kayıt yatay kartlarla gösterilir. Daha fazla kayıt varsa “Tümünü gör” aranabilir listeyi açar. Boş bölüm gösterilmez.
- Kartta içerik adı, kaldığı süre ve biliniyorsa toplam süre/ilerleme çubuğu bulunur. Dokunmak kayıtlı konumdan oynatıcıyı açar; kota ve başlatma hataları kullanıcıya gösterilir.
- Aynı kaynaktaki `S01-E02`, `S01E02` veya `1x02` biçimli bölüm adları dizi başlığıyla tek kartta toplanır. Son anlamlı izlenen bölümün konumu tutulur. Bölüm işareti bulunmayan adlarda tahmini benzerlik eşleştirmesi yapılmaz.
- Otuz saniyeden kısa açılışlar yeni kart oluşturmaz ve önceki bölümün anlamlı ilerlemesini değiştirmez. Canlı yayınlar ve geçici kişisel dosyalar bu koleksiyona alınmaz.
- Yüzde 95'i tamamlanan kayıt listeden çıkar. Daha eski bir bölümü bitirmek yeni bölümün kaydını silmez. Süre bilinmiyorsa tamamlandı kararı verilmez.
- Koleksiyon en son 30 kayıtla sınırlıdır. Yeni içerik gerektiğinde en eski kaydın yerini alır; mevcut içeriğe devam etmek kopya kart üretmez.
- Kart menüsündeki veya tam listedeki kaydırma eylemindeki “Listeden kaldır” yalnızca izleme kaydını kaldırır. Kaynak ve içerik silinmez. Aktif içerik kaldırılırsa mevcut oturumun sonraki kayıt kontrolü onu geri getirmez; açıkça yeniden oynatılması yeni bir izleme oturumudur.
- Büyük erişilebilirlik yazısında bölüm başlığı/düğmesi alt alta gelir. Kart yükseklikleri içeriğe uyarlanır; süreler gerektiğinde satır atlar ve tam listede uzun başlıklar kesilmez.

## Saklama ve geçiş

Önceki tek “son izlenen” Keychain kaydı aynı hizmet/hesap anahtarında okunur. Geçerli ilerleme yeni koleksiyona aktarılır; ilk güncellemede son kayıt ve koleksiyon tek JSON anlık görüntüsü olarak yazılır. Kayıtlı konum korunur.

İçerik adresleri giriş bilgisi taşıyabileceğinden kayıtlar bu cihaza bağlı Keychain alanında tutulur; sunucuya veya iCloud'a gönderilmez. Kaynak düzenlendiğinde/silindiğinde yalnızca o kaynağın tüm devam kayıtları temizlenir. Tüm kaynakları silmek koleksiyonu da temizler. Eski tek kayıt, canlı yayın/çok kısa izleme gibi koleksiyon dışındaki son içerik için kullanılmaya devam eder.

URL sağlayıcıdan tekrar çözümlenmez; kayıtlı yayın adresi açılır. Sağlayıcı adresi değiştirmişse oynatma hatası gösterilir. Gerçek sağlayıcıların bölüm adı biçimleri ve URL ömürleri ayrıca cihazda kontrol edilmelidir.

Yerel Türkçe/İngilizce gizlilik sitesi, gizlilik envanteri ve Netlify ZIP'i çoklu kayıt davranışıyla güncellendi. Siteye yayın yapılmadı. Beş yeni metin 22 dile çevrildi; 290 anahtar / 6380 değer doğrulaması geçti.

## Doğrulama

- iOS 26.5 / iPhone 17 Pro Max simülatöründe uygulama ve test hedefleri derlendi.
- Altı uygulama kontrolü geçti: dizi gruplama/film ayrımı/tamamlanan kayıt/kaynak temizliği; 30 kayıt sınırı ve tekrarların önlenmesi; eski Keychain biçiminden konumu koruyan geçiş; aktif kayıt kaldırıldığında tekrar oluşmaması; önceki tek kayıt davranışı; gerçek MP4 oynatıcıda konumdan devam ve kaynak silme. İlk dört ilgili sonuç `build/continue-watching-r3-20261007.xcresult` içinde test bazında; iki gerçek oynatma sonucu `build/continue-watching-r4-20261007.xcresult` içindedir.
- İki arayüz testi son koşuda geçti: üç kart sınırı; beş kayıtlı tam liste; arama/kaydırarak kaldırma; uygulamayı sonlandırıp yeniden açınca dört kaydın korunması; gerçek videonun en az kayıtlı 42. saniyeden devam etmesi; altta tek aktif oynatıcı; büyük yazı yerleşimi. Sonuç: `build/continue-watching-r5-20261007.xcresult` / `.log`, **TEST SUCCEEDED**.
- Normal, tam liste, devam edilen video, aktif oynatma ve büyük yazı görüntüleri `build/continue-watching-captures-20261007/` altında saklandı ve görsel olarak incelendi. Büyük yazıda başlık/düğme sıkışması düzeltilerek yeniden yakalandı.
- İlk iki derleme test kodundaki eksik parametre ve XCTest sorgusu nedeniyle başarısızdı. Birleşik r3 koşusunda yerel örnek medya sunucusu çalışmadığından iki gerçek oynatma testi başarısız oldu; çalışan sunucuyla r4'te geçti. Arayüz testinin üst bölüm kimliği aktarımı ve iOS 26 arama modundan çıkış adımı düzeltildi; r5 geçti. Başarısız sonuç paketleri bütünüyle başarılı sayılmıyor.
- `build/continue-watching-localization-20261007.log`: 22 dil, 290 anahtar, 6380 değer, hata yok. `git diff --check` temiz.

Yerel özgün test medyası kullanıldı; gerçek IPTV hesabı gerekmedi. PiP köşe dönüşünün ayrı durumu [PiP dönüş notlarında](PIP_RETURN_2026-10-07.md) tutulur.

Çoklu devam kayıtlarını ve sonraki PiP geometri düzenlemesini içeren imzalı Debug derleme aynı uygulama kimliğiyle bağlı iPhone'a kuruldu. Mevcut kaynak ve izleme kayıtları temizlenmedi. Kullanıcının son yönlendirmesiyle fiziksel cihazdaki son görsel kabul/testler kullanıcıya bırakıldı; sonraki doğrulama yalnız yerel testlerle yapıldı.
