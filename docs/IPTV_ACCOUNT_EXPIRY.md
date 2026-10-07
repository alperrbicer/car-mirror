# IPTV hesap bitiş tarihi

7 Ekim 2026

Kaynak kartında kaynak türünün altında, kanal listesindeyse üstte IPTV hizmetinin bitiş tarihi gösterilir. Geçmiş tarih veya sağlayıcının `Expired` durumu turuncu “IPTV süresi doldu” metniyle belirtilir. Bu bilgi Mirivo Pro aboneliği veya günlük ücretsiz izleme hakkıyla ilgili değildir.

Xtream Codes hesaplarında aynı sunucunun `player_api.php` uç noktasındaki `user_info.exp_date` alanı okunur. Kullanıcı adı/parola içeren `get.php` M3U bağlantılarında da aynı sorgu desteklenir; sunucunun alt dizini, portu, kodlanmış giriş bilgileri ve ek sağlayıcı parametreleri korunur. Normal M3U dosyaları ve doğrudan yayın bağlantıları için hesap API’si tahmin edilmez.

Sayısal veya metin biçimindeki Unix zaman damgaları desteklenir. Tarih cihazın saat dilimi ve uygulama dilinde gösterilir. Boş, null, sıfır veya geçersiz bir değer sınırsız hizmet olarak yorumlanmaz: “Bitiş tarihi paylaşılmıyor” yazılır. İlk isteğin başarısız olması halinde “Bitiş tarihi alınamadı” görünür.

Son başarılı sonuç cihazda saklanır. Yenileme başarısızsa önceki tarih, son kontrol zamanıyla birlikte gösterilir. Listeye giriş ve uygulamaya dönüşte 15 dakikadan eski bilgi yenilenir; hatalar bir dakika boyunca yeniden otomatik denenmez. Kaynak menüsündeki “Bilgileri yenile” veya kanal listesini aşağı çekme önbelleği beklemeden yeniler. Düzenleme, silme ve tüm kaynakları temizleme işlemleri ilgili hesap bilgisini de temizler. Ad veya kaynak türü aynı kalsa bile giriş bilgisi değişikliği yeni hesap bilgisini otomatik sorgular. Eşzamanlı istekler birleştirilir; silinmiş/düzenlenmiş kaynağın geç yanıtı yayımlanmaz.

Menüden yenileme sürerken ilgili kaynak kartında üç noktanın yerinde spinner görünür; kayıtlı bilgi kaybolmaz. Aynı kaynak için ikinci manuel yenileme başlatılamaz. İşlem başarıyla veya hatayla bitince spinner kaldırılır. “Sil” seçeneği çöp kutusu simgesiyle gösterilir.

Hesap bilgisi kanal yüklemesinden bağımsız alınır; hata veya eksik bilgi oynatmayı engellemez. Giriş bilgileri Keychain’de kalır. Sağlayıcının ham yanıtı, adresi ve giriş bilgileri hesap önbelleğine yazılmaz. İstek geçici URLSession ile, 15 saniyelik toplam süre ve 64 KiB yanıt sınırıyla yapılır.

API biçimi için incelenen birincil uygulama: [XtreamCodesExtendAPI player_api.php](https://github.com/gtaman92/XtreamCodesExtendAPI/blob/master/player_api.php). Gerçek sağlayıcının bu alanları sunması ve API erişimine izin vermesi gerekir.

## Doğrulama

- `build/iptv-expiry-core-20261007.log`: 20 ProductTests geçti; dört yeni test uç nokta üretimi, kodlanmış bilgiler, farklı tarih biçimleri, eksik/bozuk tarihler ve reddedilmiş hesapları kapsar.
- `build/iptv-expiry-localization-20261007.log`: 22 dil, 277 anahtar; eksik çeviri, biçim parametresi veya Apple strings hatası yok.
- `build/iptv-expiry-verified-20261007.log` / `.xcresult`: Beş uygulama testi geçti. Ön belleğin kalıcılığı ve süresi, yenileme hatasında eski tarih, istek birleştirme, geç yanıtın elenmesi, kanal önbelleğinden bağımsızlık ve kaynağın adı değişmeden giriş bilgisi düzenlemesi doğrulandı. Bu birleşik koşunun UI testi sistem parola penceresi nedeniyle başarısızdı; paketin tamamı başarılı sayılmaz.
- `build/iptv-expiry-ui-final-20261007.log` / `.xcresult`: Dört senaryolu arayüz testi geçti (`TEST SUCCEEDED`). Aktif hesap ve süresi dolan hesap tarihleri kaynak kartında/kanal listesinde göründü; eksik tarih ve HTTP 503 yanıtında da kanal listesi açıldı. iOS parola kaydetme penceresi testte kapatıldı. Önceki UI koşuları boş tarih karşılaştırması ve sistem parola penceresi nedeniyle başarılı değildi; geçerli UI sonucu bu son koşudur.
- Sekiz güncel görsel `build/iptv-expiry-20261007/` altında saklanır. Aktif hesap kaynak kartı, kanal listesi ve süresi dolmuş hesap kartı görsel olarak da kontrol edildi.
- Gerçek IPTV sağlayıcısı veya fiziksel cihaz bu çalışmanın doğrulama kapsamında değildir. Test sunucusu yalnızca sentetik hesap bilgileri ve özgün yerel demo videosunu kullanır; uygulamaya paketlenmez.
