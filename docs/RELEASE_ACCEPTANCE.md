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

Netlify sayfaları kullanıcı tarafından yayımlanacak. Gerçek alan adı ve çalışan gizlilik/destek URL'leri App Store Connect'e girilir. CarPlay yetkileri ve dağıtım profilleri mevcut olduğunda build 1.0 hazırlanır; TestFlight üzerinden aynı fiziksel kabul akışı tekrarlanır. Mağaza ekran görüntüleri final build ile eşleştirilir. App Review gönderimi ve yayındaki uygulamanın mağazadan kurulumu ayrıca doğrulanır.

Pro için mağazada ürün oluşturma, gerçek fiyat/ülke seçimi ve sandbox satın alma testleri satış açılacağı zamana aittir. İlk sürümde satış kapalı olduğundan ürünlerin yokluğu ücretsiz sürümü kilitlemez.
