# Mirivo dil kapsamı

3 Ekim 2026: Kullanıcının talimatıyla ertelenen altı dil eklendi. Uygulama ve yayın uzantısı **22 dil** içeriyor.

Türkçe (`tr`), İngilizce (`en`), Basitleştirilmiş Çince (`zh-Hans`), Geleneksel Çince (`zh-Hant`), Japonca (`ja`), Korece (`ko`), Fransızca (`fr`), Almanca (`de`), İspanyolca (`es`), İtalyanca (`it`), Brezilya Portekizcesi (`pt-BR`), Rusça (`ru`), Felemenkçe (`nl`), Lehçe (`pl`), İsveççe (`sv`), Ukraynaca (`uk`), Arapça (`ar`), İbranice (`he`), Tayca (`th`), Vietnamca (`vi`), Endonezce (`id`) ve Hintçe (`hi`).

## Davranış

Uygulama dili ayarlardan aranarak seçilir veya sistem tercihleri izlenir. Dilin kendi adı, seçili dildeki adı, İngilizce adı veya kodu aranabilir. Bölgesel dil kodları desteklenen uygulama diline eşlenir. Çince için açık yazı sistemi bölgeden önce gelir; Tayvan, Hong Kong ve Makao varsayılan olarak geleneksel Çince kullanır. Portekizce Brezilya çevirisine eşlenir. Desteklenmeyen tercihlerde listedeki sonraki desteklenen dil, hiçbiri yoksa İngilizce kullanılır.

Arayüz ve yayın uzantısı aynı çevirileri kullanır. Sistem satın alma, ReplayKit ve yerel oynatıcı denetimlerinin dili iOS tarafından yönetilir. Hukuki belgeler ve yardım içeriği Türkçe/İngilizce sunulur; uygulama Türkçe arayüz için /tr/, diğer diller için /en/ Netlify sayfalarını açar. Dil değişimi site üzerinden yapılır. Yeni altı arayüz dili, cihazın altı yeni SpeechAnalyzer konuşma modeli desteklediği anlamına gelmez.

Arapça ve İbranice, ana arayüz ve gerçek harici ekranın SwiftUI görünümünde sağdan sola düzen kullanır. Kaynak adı doğal metin yönünü korur; URL, kullanıcı adı ve parola alanları soldan sağa düzenlenir. İngilizce/Türkçe HTML belgeleri kendi metin yönlerini korur. CarPlay şablonlarının ve sistem oynatıcısının düzenini iOS yönetir.

Birleşen harflerin ve sesli işaretlerin ayrılmaması için Arapça, İbranice, Tayca ve Hintçe başlıklarda ilave harf aralığı uygulanmaz. Dil değiştirildiğinde açık ayarlar sayfasının yönü de güncellenir.

Marka ve teknik biçim adları çevrilmez. Bağımsız ana dil editörü incelemesi yapılmadı.

## Doğrulama

Güncel kaynakta her dilde 207 uygulama metni ve yerel ağ izin açıklaması bulunur. Yeni altı dilde 1.242 metin ve altı izin açıklaması çevrildi; kaynak düzenleme, oynatıcı ve günlük izleme bilgileri için sonradan eklenen 24 anahtar da bu kapsamdadır. `Config/Localizations.json`, ana uygulama/uzantı plist’leri, dil seçimi ve Xcode kaynak grupları aynı 22 dili içerir.

- `python3 scripts/verify_release.py`: 22 dilin anahtar, boş değer, Apple strings biçimi ve biçim parametresi kontrolleri geçti. Rapor: `build/release-static-checks.json`.
- `swift test --filter LanguageTests`: güncel kaynakta bölgesel eşleme, yeni altı dilin açık seçimi, yerel ad/arama, 22 dil yapılandırması ve RTL davranışını kapsayan dört test geçti. Kayıt: `build/localization22-language-tests.log`. İlk uygulama aşamasında 35 çekirdek/medya testi de geçmişti (`build/localization22-core.log`); bu eski sonuç daha sonra değişen oynatıcı kapsamını doğrulamaz.
- Derlenmiş simülatör uygulaması ve yayın uzantısı: 22 dil paketi mevcut; yeni altı dilin 207 anahtarı kaynak kataloglarıyla aynı. Kayıt: `build/localization22-bundle-validation.json`.
- İlk 22 dil açılış testi geçti (`build/localization22-ui.log`). Son tipografi değişikliklerinden sonra yeni altı dil açılışı ve Arapça seçiminin yeniden açılışta korunup sistem diline dönmesi geçti: `build/localization22-isolated.xcresult` içindeki `testAddedLanguagesLaunch` ve `testRightToLeftLanguageSelectionPersistsAndReturnsToSystem`.
- Arapça ve İbranice kaynak girişi geçti: URL ve kullanıcı adı değişmeden kaldı, parola girildi ve kaynak kaydedildi. Sonuç: `build/localization22-rtl-flows.xcresult` içindeki `testRightToLeftSourceEntry`.
- Arapça ve İbranice gizlilik bağlantıları İngilizce çevrimdışı belgeyi açtı; İngilizce belge seçimi doğrulandı. Sonuç: `build/localization22-legal.xcresult` içindeki `testRightToLeftLegalFallback` (**TEST SUCCEEDED**).
- Sonuçlar ayrı koşulardaki test bazında kaydedilmiştir. İlk birleşik koşular test kaydırması, klavye ve iOS parola kaydetme penceresi nedeniyle başarısızdı; bu paketlerin tamamı başarılı sayılmaz. İlgili testler düzeltilip yukarıdaki son koşularda geçti. Görseller: `build/localization22-screenshots/`, `build/localization22-rtl-screenshots/`, `build/localization22-legal-screenshots/`.
- Fiziksel cihaz, harici ekran ve araç kabulü bu çalışmada yapılmadı.

2 Ekim’deki önceki 16 dil koşuları ve son belge gezinme kontrolünün açık durumu `docs/IMPLEMENTATION_STATUS.md` içinde tarihsel kayıt olarak korunur. Bu sonuçlar yeni altı dilin doğrulaması olarak kullanılmaz.

5 Ekim 2026: Yerel belge görüntüleyicisi kaldırıldı. Arapça/İbranice gizlilik bağlantıları Safari’de İngilizce Netlify sayfasını açtı (`testRightToLeftWebsiteFallback`, `build/netlify-links-ui-verified-20261005.log`, test bazında geçti). Eski çevrimdışı belge testleri tarihsel kayıttır.

7 Ekim 2026: IPTV hesap bitiş tarihi için sekiz metin 22 dile eklendi. Güncel kataloglarda 277 anahtar var. `build/iptv-expiry-localization-20261007.log` içindeki anahtar, biçim parametresi ve Apple strings kontrolleri geçti. Tarih, seçili uygulama dilinde biçimlendirilir. Davranış ve test kapsamı: [IPTV hesap bitiş tarihi](IPTV_ACCOUNT_EXPIRY.md).

Dosyadan oynatma listesi ekleme ile 3 anahtar daha eklendi; güncel toplam 22 dilde 280 anahtar ve 6160 çevrilmiş değerdir. `build/source-methods-localization-20261007.log` doğrulaması başarılıdır.

Son izlenen içerik, görünür yenileme ve ses/altyazı seçiminde 5 anahtar daha eklendi. Güncel katalog 22 dilde 285 anahtar ve 6270 değer içerir; `build/playback-options-localization-20261007.log` doğrulaması başarılıdır.

Birden fazla film/dizi için devam etme alanında 5 anahtar daha eklendi. Güncel katalog 22 dilde 290 anahtar ve 6380 değer içerir; `build/continue-watching-localization-20261007.log` doğrulaması başarılıdır. Anahtar eşliği, biçim parametreleri ve Apple strings sözdizimi kontrol edildi.
