# Mirivo dil kapsamı

3 Ekim 2026: Kullanıcının talimatıyla ertelenen altı dil eklendi. Uygulama ve yayın uzantısı **22 dil** içeriyor.

Türkçe (`tr`), İngilizce (`en`), Basitleştirilmiş Çince (`zh-Hans`), Geleneksel Çince (`zh-Hant`), Japonca (`ja`), Korece (`ko`), Fransızca (`fr`), Almanca (`de`), İspanyolca (`es`), İtalyanca (`it`), Brezilya Portekizcesi (`pt-BR`), Rusça (`ru`), Felemenkçe (`nl`), Lehçe (`pl`), İsveççe (`sv`), Ukraynaca (`uk`), Arapça (`ar`), İbranice (`he`), Tayca (`th`), Vietnamca (`vi`), Endonezce (`id`) ve Hintçe (`hi`).

## Davranış

Uygulama dili ayarlardan aranarak seçilir veya sistem tercihleri izlenir. Dilin kendi adı, seçili dildeki adı, İngilizce adı veya kodu aranabilir. Bölgesel dil kodları desteklenen uygulama diline eşlenir. Çince için açık yazı sistemi bölgeden önce gelir; Tayvan, Hong Kong ve Makao varsayılan olarak geleneksel Çince kullanır. Portekizce Brezilya çevirisine eşlenir. Desteklenmeyen tercihlerde listedeki sonraki desteklenen dil, hiçbiri yoksa İngilizce kullanılır.

Arayüz ve yayın uzantısı aynı çevirileri kullanır. Sistem satın alma, ReplayKit ve yerel oynatıcı denetimlerinin dili iOS tarafından yönetilir. Hukuki belgeler ve yardım içeriği Türkçe/İngilizce sunulur; belge görünümünde dil seçimi vardır. Yeni altı arayüz dili, cihazın altı yeni SpeechAnalyzer konuşma modeli desteklediği anlamına gelmez.

Arapça ve İbranice, ana arayüz ve gerçek harici ekranın SwiftUI görünümünde sağdan sola düzen kullanır. Kaynak adı doğal metin yönünü korur; URL, kullanıcı adı ve parola alanları soldan sağa düzenlenir. İngilizce/Türkçe HTML belgeleri kendi metin yönlerini korur. CarPlay şablonlarının ve sistem oynatıcısının düzenini iOS yönetir.

Marka ve teknik biçim adları çevrilmez. Bağımsız ana dil editörü incelemesi yapılmadı.

## Doğrulama

Her dilde 183 uygulama metni ve yerel ağ izin açıklaması bulunur: toplam 4.026 arayüz çevirisi. `Config/Localizations.json`, ana uygulama/uzantı plist’leri, dil seçimi ve Xcode kaynak grupları aynı 22 dili içerir.

- `python3 scripts/verify_release.py`: 22 dilin anahtar, boş değer, Apple strings biçimi ve biçim parametresi kontrolleri geçti. Rapor: `build/release-static-checks.json`.
- `swift test`: bölgesel eşleme, yeni altı dilin açık seçimi, yerel ad/arama ve yalnız Arapça/İbranice için RTL davranışı dahil 35 çekirdek ve medya testi geçti. Kayıt: `build/localization22-core.log`.
- 22 dilde açılış, RTL kaynak girişi ve dil seçiminin korunması için simülatör testleri eklendi. Bu koşunun sonuçları tamamlandığında burada kaydedilecek; fiziksel cihaz ve araç kabulü ayrı iş olarak kalıyor.

2 Ekim’deki önceki 16 dil koşuları ve son belge gezinme kontrolünün açık durumu `docs/IMPLEMENTATION_STATUS.md` içinde tarihsel kayıt olarak korunur. Bu sonuçlar yeni altı dilin doğrulaması olarak kullanılmaz.
