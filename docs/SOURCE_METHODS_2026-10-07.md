# Kaynak yöntemleri — 7 Ekim 2026

| Yöntem | Davranış |
| --- | --- |
| M3U oynatma listesi | Mevcut HTTP(S) liste akışı korunur. Kullanıcı bu yöntemi kendi sağlayıcısıyla doğruladı. |
| Yayın bağlantısı | HTTP(S) yayın/medya adresini tek içerik olarak açar; oynatıcı desteklediği biçime göre native veya VideoLAN motorunu kullanır. Sağlayıcılarda güvenilir olmadığı için HEAD isteğiyle yapay bir erişim kontrolü uygulanmaz. |
| Xtream Codes | Sunucu kökü, alt dizin, `get.php` veya `player_api.php` adresi kabul edilir. Standart `get.php` oynatma listesi kullanıcı adı/parola ile istenir. Tam uç nokta bağlantısındaki bilgiler ayrı alanlar boşken kullanılabilir; alanlar doldurulmuşsa onlar geçerlidir. |
| Dosyadan oynatma listesi | Apple dosya seçicisiyle M3U/M3U8 seçilir. Dosya doğrulanıp uygulamanın korumalı alanına kopyalanır. Asıl dosya silinmez veya değiştirilmez. |

## Düzeltmeler

- Xtream sunucu alanına tam API/liste adresi yapıştırınca ikinci kez `get.php` eklenmesi düzeltildi. Port, sunucu alt dizini ve ek sağlayıcı sorgu parametreleri korunur. Eski `action`, `type`, `output` ve giriş alanları tekil olarak yeniden oluşturulur.
- PHP sorgu çözümlemesi `+` karakterini boşluk olarak yorumlar. Kullanıcı adı, parola ve ek parametrelerdeki artılar `%2B` kodlanır; `&`, `=` gibi karakterler yeni alan ekleyemez.
- Xtream ekleme aşaması da düzenleme gibi adres/giriş biçimini doğrular. Hatalı HTTP yanıtı, HTML/JSON hata gövdesi veya boş liste oynatılabilir kanal sayılmaz. Gerçek hesap doğrulaması liste yüklenirken sağlayıcının yanıtıyla yapılır.
- Dosya kaynağı geçici seçici adresine bağımlı değildir. Yeniden uygulama açılışında kayıtlı kopya yüklenir; dosya değiştirildiğinde eski kopya, kaynak silindiğinde ilgili kopya temizlenir. Kaynak türünü dosyadan bağlantıya çevirmek de kopyayı kaldırır. Ücretsiz bir kaynak sınırı geçerlidir.
- Dosya en fazla 5 MiB, liste en fazla 20.000 içerik kabul eder. Dosyadan içe aktarma HTTP(S) yayın adresleri içindir; başka yerel dosyalara erişim ve yerel HLS segment listesi bu yöntemle desteklenmez.
- Kaynak bilgileri ve girişler Keychain’de tutulur. İçe aktarılan listenin kendisi yayın adresleri/girişler içerebilir; bu kullanıcı seçimiyle alınan kopya dosya koruması ve yedekleme dışı uygulama alanında tutulur. İnternetten yüklenen kanal listelerinin önbelleği hâlâ yalnızca bellektedir.
- Hesap bitiş tarihi [IPTV hesap notlarında](IPTV_ACCOUNT_EXPIRY.md) açıklanır. Yerel dosya ve doğrudan yayın için hesap API’si tahmin edilmez.

## Doğrulama

- `build/source-methods-core-20261007.log`: 21 çekirdek testi geçti. Sunucu/uç nokta normalleştirmesi, kodlanmış parola ve sağlayıcı alt dizini/portu kontrol edildi.
- `build/source-methods-unit-20261007.log` / `.xcresult`: 5/5 uygulama testi geçti. Doğrudan bağlantı ve Xtream kaynaklarından HTTP video çözümleme, doğru/yanlış giriş, tam API adresi, bozuk yanıt, dosya içe aktarma/yeniden açma/değiştirme/silme ve ücretsiz sınır kontrol edildi. Video testi iki yöntemde de gerçekten yeni piksel kareleri üretildiğini doğrular.
- `build/source-methods-ui-20261007.log` / `.xcresult`: 2/2 yakalama politikası testi ve 2/2 arayüz testi geçti; koşu `TEST SUCCEEDED` ile tamamlandı. Doğrudan kaynak arayüzden eklenip oynatıldı; dosya seçici açıldı/iptal edildi; tam `player_api.php` adresinden eklenen Xtream dahil dört hesap bitiş tarihi senaryosu doğrulandı.
- Dosya kopyalama ve liste yükleme uygulama testinde gerçek yerel dosyalarla kontrol edildi. Arayüz testi Apple dosya seçicisinin açılışını kontrol eder; fiziksel iCloud Drive hesabından dosya indirme kanıtı değildir.
- `build/source-methods-localization-20261007.log`: 22 dil, 280 anahtar, 6160 çeviri; hata yok.
- 11 ekran görüntüsü `build/source-methods-20261007/` altında saklanır. Dosya kaynak ekranı ve doğrudan video oynatımı görsel olarak incelendi.
- Testler yerel sentetik sağlayıcı ve özgün demo medyası kullanır. Gerçek sağlayıcı erişimi, CarPlay/TV ve fiziksel iPhone bu turun kanıtı değildir. Stalker/Ministra portal protokolü bu kaynak yöntemlerine dahil değildir.

## PiP ve dağıtım durumu

Kullanıcının talebiyle VideoLAN ekran yakalama kısıtlaması geçici kaldırıldı; PiP köşe geçişinden örnek alınabilir. Değişiklik yeni derlemede geçerlidir. Bu turda fiziksel cihaza kurulum veya TestFlight yüklemesi yapılmadı; köşe geçişi çözülmüş sayılmıyor. Ayrıntılar [oynatıcı düzeltme notlarında](PLAYER_FIXES_2026-10-07.md).

Yerel destek sitesi ve gizlilik envanteri yeni dosya saklama/hesap bilgisiyle ve ücretsiz araç modu davranışıyla güncellendi. `Release/mirivo-netlify.zip` yeniden üretildi; siteye yayımlanmadı.
