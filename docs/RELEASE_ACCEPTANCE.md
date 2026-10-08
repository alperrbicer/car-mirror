> 8 Ekim 2026 güncellemesi: CarPlay kaldırılmıştır. Aşağıdaki CarPlay/build 12 kayıtları tarihsel kanıttır; güncel dağıtım için DEPLOYMENT.md ve CARPLAY_REMOVAL_2026-10-08.md esas alınmalıdır.

# Mirivo 1.0 kabul kaydı

Bu dosya testlerin yerine geçmez. Tamamlanmış yerel doğrulamaların çıktıları IMPLEMENTATION_STATUS.md içinde listelenir. Aşağıdaki fiziksel ölçümler şu anda elde edilmedi.

## Fiziksel cihaz ve araç

Aynı dağıtım adayı ile iPhone 16 Pro + 2024 Kia EV6: doğrudan kablo ve markasız kablosuz adaptör ayrı oturumlar. iOS, araç yazılımı, bağlantı biçimi ve build kaydedilir.

Audio onayı sonrası ilk kabul: Audio imzalı Mirivo simgesini açma, iPhone'dan eklenen kaynağı CarPlay'de seçme, sesin araç hoparlörüne ulaşması, Şu An Çalıyor başlığı ve oynat/duraklat/durdur kontrolleri. Telefon görüşmesi, bağlantı kopması ve yeniden bağlanma da sınanır. Audio sürümünün araç menüsünde ekran paylaşımı veya video bağlantı testi bulunmamalıdır. Bu akış aşağıdaki Video kabulünün tamamlandığı anlamına gelmez.

1. Yetkili gerçek imza, CarPlay simgesi ve sahne açılışı.
2. Araç ekranında sürekli değişen test görüntüsü; yalnız capture veya AVPlayer bayrağı yeterli değildir.
3. YouTube ve Smarters Player ile görüntü/uygulama sesi; uygulamalar arası geçiş, dikey/yatay yön ve park durumundaki sistem davranışı.
4. Her kaynakta 30 dakika: uzantı bellek sınırı, ısı, düşen kareler, donma ve kesinti kaydı.
5. Aynı kaynaktan görsel işaret ve ses ile gecikme/senkron ölçümü. “Görüntüyle birlikte” ve “Kaynak uygulamadan” ayrı ölçülür; çift ses ve kaynağın durması kontrol edilir.
6. 10 başlat/durdur, kesilen kablo, bağlantı geri gelişi, telefon kilidi, telefon görüşmesi/kesinti, düşük güç ve uygulamanın yeniden açılması.
7. Canlı altyazı: desteklenen dil modeli, iPhone 16 Pro'da yayın uzantısının bellek kullanımı ve gerçek konuşma sonucu. Desteklenmeyen dil/cihaz açık hata verir; sunucuya geri dönüş yoktur.
8. Güncel markanın fiziksel görünümü, büyük yazı, VoiceOver, Hareketi Azalt; tanılama paylaşımı ve silme.

## Dağıtım

Netlify sayfaları 5 Ekim 2026 tarihinde yayımlandı; uygulama Türkçe/İngilizce sayfalara Safari üzerinden açılır. Sonraki gizlilik/koşul güncellemesi yerel hazırlanmış, henüz yayımlanmamıştır. 1.0 (12) CarPlay Audio dağıtım adayı App Store Connect'te mevcut ve sürüm 1.0'a seçilerek kaydedildi. Apple metadata durumu Validated. Bu aday CarPlay Video yetkisi içermez. TestFlight üzerinden aynı fiziksel kabul akışı ayrıca tamamlanmalıdır. 22 dilde 132 iPhone mağaza görüntüsü yüklendi; ortak sıra ve aynı dilde boyut devralması sayfa yenilemesinden sonra doğrulandı. Video yetkili sonraki adayın gerçek araç görüntüleri ayrıca hazırlanmalıdır. App Review gönderimi ve yayındaki uygulamanın mağazadan kurulumu ayrıca doğrulanır.

Pro satışları açıktır. Yalnız yıllık ve ömür boyu ürün aktiftir; iki ürünün inceleme ekranları App Store Connect'e yüklendi. Ürün ve fiyat kaydı canlı satın alma kanıtı değildir. Apple sandbox/TestFlight satın alma, geri yükleme, iade, abonelik bitişi ve RevenueCat bildirim doğrulaması henüz tamamlanmadı. Paid Apps Agreement ve vergi/banka bilgileri de satış hazırlığının parçasıdır. Güncel durum ve kalan adımlar docs/APP_STORE_READINESS_2026-10-05.md içindedir.

Build 12 kendi Mirivo Internal Testers grubuna eklendi ve yenileme sonrası Testing görüldü; tek testçi hesap sahibi. Davetin son 5 Ekim kontrolü Invited; TR/EN kabul notları kaydedilip yenilemeyle doğrulandı. Bu, fiziksel kurulumu veya başarılı ödemeyi kanıtlamaz. İki ürünün toplam 44 yerelleştirmesi, grubun 22 yerelleştirmesi ve 22 gizlilik URL'si kalıcı olarak doğrulandı. Ana uygulama 175 ülkede ücretsiz; üç ürün/grup öğesi aynı inceleme taslağında. Sürümün eklenmesini App Privacy, Content Rights ve Age Ratings engelliyor. Yedi gizlilik veri türü ile tüm amaç/bağlantı/tracking cevapları taslağa kaydedildi ve yenilemeyle doğrulandı. Publish açık, son hesap sahibi yayını yapılmadı. Canlı Business kontrolünde banka hesabı yok, vergi formu eksik ve Paid Apps Pending User Info.

5 Ekim reklam sözü düzeltmesi: 1.0 (12) yüklendi; 6 Ekim kontrolünde Apple'da Validated, sürüm 1.0'a kaydedilmiş ve kendi internal grubunda Testing. İki yeni Pro inceleme görseli yenilemeyle doğrulandı; üç ürün/grup öğesi aynı taslakta. Yeni adayda 22 dil için kalıcı reklam sözü yok. Site düzeltmesi yayında; bekleyen gizlilik/koşul metni bu kapsamda yayımlanmadı. RevenueCat yearly/lifetime varsayılan eşleştirmeleri ve anonim kimlik/entegrasyon davranışı kontrol edildi; dört anonim kayıt, sıfır ücretli abone/gelir satın alma kabulünün hâlâ gerekli olduğunu gösterir.
