# Mirivo — kaldığımız yer

Son kayıt: 3 Ekim 2026. Proje: `/Users/alperbicer/Documents/projects/private/car-mirror`.

Asıl hedef iPhone 16 Pro'daki YouTube ve Smarters Player gibi uygulamaların görüntüsünü 2024 Kia EV6'nın orijinal ekranına aktarmaktır. Audio onayı ve çalışan yerel ses testleri bu görüntü hedefinin tamamlandığı anlamına gelmez. Kablo ve markasız kablosuz CarPlay adaptörü ayrı doğrulanacak.

## Tamamlanan son çalışma

- Kaynak sürüm 1.0 (6), Mirivo + A grafit/mint kimliği.
- Apple CarPlay Audio onayı alındı. Xcode üzerinden Audio geliştirme profili oluşturuldu; imzalı Release derlemesi, gerçek kod imzası ve App Group eşleşmesi doğrulandı.
- Varsayılan `CarMirror` yapılandırması Audio; `CarMirror CarPlay` veya `--carplay-video` Audio + Video ister. Video onayı/profili henüz doğrulanmadı.
- CarPlay kaynak seçimi, ses oynatma, Şu An Çalıyor ve oynat/duraklat/durdur bağlantıları uygulandı.
- 34 Swift, 17 kurulum ve 2 uygulama içi ses testi geçti. Son paket kontrolü: `build/carplay-audio-validation.json`.
- 3 Ekim’de ertelenen altı dil eklendi; uygulama ve yayın uzantısı artık 22 dil içeriyor. Arapça/İbranice sağdan sola düzen kullanıyor. Doğrulama kaydı `docs/LOCALIZATION.md` içinde. Pro hazırlığı ve Türkçe/İngilizce Netlify belgeleri hazır; uygulama doğrudan canlı sayfalara link verir. Güncel Netlify paketi: `Release/mirivo-netlify.zip`.

## Sıradaki işler

1. **Güncel sürümü fiziksel iPhone'a kurmak.** Audio imzalı build 6 henüz telefona yüklenmedi. Son doğrulanmış telefon kurulumu 0.1.0 (4), CarPlay yetkisi olmayan önizlemedir. Yeni oturumda cihaz, kaynak değişiklikleri ve profil geçerliliği yeniden kontrol edilecek; derleme, kurulum, açılış ve görünür ekran ayrı kaydedilecek.
2. **Audio sürümünü EV6'da doğrulamak.** Mirivo simgesinin görünmesi, sahnenin açılması, kaynak seçimi, araç hoparlöründen ses, başlık ve araç oynatma kontrolleri. Telefon görüşmesi, kopma/yeniden bağlanma ve başlat/durdur senaryoları; kablo ve adaptör için ayrı sonuç.
3. **CarPlay Video sonucunu kontrol etmek.** Mevcut e-posta yalnız Audio onayını doğruluyor. Video onayı, App ID'deki yetki ve geliştirme/dağıtım profilleri doğrulanacak. Video yapılandırması gerçek imza kontrolünden geçmeden görüntü desteği tamamlandı sayılmayacak.
4. **Gerçek ekran yansıtmayı tamamlamak ve ölçmek.** Video yetkili sürümde sürekli değişen görüntü, YouTube/Smarters Player, ses-görüntü senkronu, çift ses, yön değişimi, 30 dakikalık kullanım, 10 başlat/durdur ve bağlantı kesintileri. ReplayKit'in başlaması veya AVPlayer bayrağı araçta görüntü kanıtı sayılmayacak. Sorun çıkarsa ölçülen çıkış yoluna göre aktarım kodu düzeltilecek.
5. **Canlı altyazıyı fiziksel yayın uzantısında test etmek.** Desteklenen konuşma modeli, gerçek konuşma, bellek sınırı, ısı ve uzun yayın. 16 arayüz dili, 16 konuşma modeli desteği anlamına gelmez.
6. **Son belge gezinme değişikliğini ekranda doğrulamak.** HTML dil/sayfa bağlantıları ile yerel başlık ve Türkçe/İngilizce seçiminin eşleşmesi henüz görsel olarak doğrulanmadı. Önceki denemelerde simülatör dokunmaları ve bilgisayar kontrol erişimi sonuç vermedi; neden kesinleşmedi. İlgili testler ve gerekirse düzeltme tamamlanacak.
7. **Fiziksel tasarım ve erişilebilirlik kabulünü tamamlamak.** Güncel logo/açılış, iPhone ve CarPlay görünümü, büyük yazı, VoiceOver, Hareketi Azalt, kayıt paylaşımı/silme. Önceki simülatör sonuçları fiziksel kabulün yerine geçmez.
8. **Web ve mağaza teslimini tamamlamak.** ZIP 3 Ekim 2026’da https://mirivo-support.netlify.app adresine yüklendi; 12 sayfa HTTP ve belge metni karşılaştırmasıyla doğrulandı. Türkçe ve İngilizce (ABD) gizlilik, destek ve pazarlama URL’leri App Store Connect’e kaydedildi. Mağaza açıklaması, ekran görüntüleri ve inceleme videosu seçilen sürümün gerçekten doğrulanan özelliklerine göre hazırlanacak; Audio sürümünde CarPlay ekran yansıtma varmış gibi tanıtım yapılmayacak.
9. **TestFlight inceleme sonucu ve fiziksel kabul.** 3 Ekim 2026’da Audio adayı 1.0 (7) imzalı arşiv/IPA olarak doğrulandı, Apple’a yüklendi ve Mirivo Beta dış test grubuyla beta incelemesine gönderildi. Canlı durum: **Waiting for Review**. Türkçe/İngilizce beta bilgileri ve kullanıcı onaylı inceleme iletişimi kaydedildi. Test kullanıcısı/davet/public link yok; otomatik bildirim kapalı. Apple onayından sonra TestFlight üzerinden fiziksel kabul yapılacak; App Store yayın incelemesi ve mağazadan kurulum ayrıca tamamlanacak. Kanıt: `build/deploy/testflight-upload.json`. App Store Connect kaydı: `6818560405`, iOS 1.0 mağaza taslağı.
10. **Pro satışını daha sonraki aşamada açmak.** StoreKit satın alma, geri yükleme, iade ve abonelik bitişi henüz doğrulanmadı. Çalışan StoreKit Test ortamı ve gerçek sandbox senaryoları tamamlanacak. Ürünler/fiyatlar/ülkeler App Store Connect'te yapılandırılacak; ticari paket kullanıcıyla kesinleştirilecek. Satış açılışı mevcut ücretsiz sürümün tesliminden ayrı iş olarak tutulacak.

## Korunacak kararlar

- Pro satışları kapalı: `MIRIVO_PRO_SALES_ENABLED = NO`. Mevcut özellikler ücretsiz; mevcut sürüm reklamsız; gelecekteki tüm sürümler için reklam taahhüdü verilmez.
- Destek `alperrbicer@gmail.com`, yayıncı Alper Biçer.
- Kullanıcının 3 Ekim talimatıyla Arapça, İbranice, Tayca, Vietnamca, Endonezce ve Hintçe eklendi; kapsam 22 dil. Bu çalışma dil kapsamıyla sınırlı; diğer açık işler sonraki aşamada ele alınacak. Çevirilerin bağımsız ana dil editörü incelemesi yapılmadı.
- Netlify'a yayımlama kullanıcıya ait. Son Audio çalışmasında Chrome kullanılmadı; profil işlemleri Xcode üzerinden yapıldı.
- Başarılı yerel test, geliştirme imzası, fiziksel araç sonucu, dağıtım imzası ve Apple inceleme onayı ayrı kanıtlardır.

## Devam ederken okunacak dosyalar

- `docs/IMPLEMENTATION_STATUS.md`: tamamlanan işlemler, açık kontroller ve kanıt yolları.
- `docs/DEPLOYMENT.md`: Audio/Video/önizleme komutları ve profil doğrulaması.
- `docs/RELEASE_ACCEPTANCE.md`: fiziksel araç ve dağıtım kabul ölçütleri.
- `docs/PRO_RELEASE.md`: satış açılışı ve StoreKit işleri.
- `docs/LOCALIZATION.md`: mevcut 22 dil ve sağdan sola düzen doğrulaması.
- `Release/AppStore/review-notes.txt`: inceleme akışı ve sürümün doğru tanıtılması.

Yeni oturumun ilk adımı `git status` ile commit/staging durumunu ve mevcut kaynakları kontrol etmektir. Bu not, değişikliklerin commit/push edildiğine dair kanıt değildir. `build/` altındaki kanıtlar yereldir ve dizin temizlenirse silinebilir; geçmiş bir testin geçtiğini yeni kaynak için yeniden kullanma.
