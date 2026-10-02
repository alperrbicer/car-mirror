# Mirivo dil kapsamı

2 Ekim 2026: Kullanıcı, çalışmanın **16 dille** tamamlanmasını istedi.

Türkçe (`tr`), İngilizce (`en`), Basitleştirilmiş Çince (`zh-Hans`), Geleneksel Çince (`zh-Hant`), Japonca (`ja`), Korece (`ko`), Fransızca (`fr`), Almanca (`de`), İspanyolca (`es`), İtalyanca (`it`), Brezilya Portekizcesi (`pt-BR`), Rusça (`ru`), Felemenkçe (`nl`), Lehçe (`pl`), İsveççe (`sv`) ve Ukraynaca (`uk`).

## Sonraki çalışma

Kullanıcının açık kararıyla şu altı dil **ertelendi**. Bu sürümün dil seçimine, çeviri kaynaklarına veya mağaza dil listesine dahil edilmez:

- Arapça (`ar`)
- İbranice (`he`)
- Tayca (`th`)
- Vietnamca (`vi`)
- Endonezce (`id`)
- Hintçe (`hi`)

Arapça ve İbranice eklenirken sağdan sola düzen; gezinme, formlar, oynatıcı ve karışık URL/metin alanları üzerinde ayrıca test edilecek. Bu çalışma için RTL doğrulaması yapılmış sayılmaz.

## Davranış

Uygulama dili ayarlardan aranarak seçilir veya sistem tercihleri izlenir. Bölgesel dil kodları desteklenen uygulama diline eşlenir. Çince için açık yazı sistemi bölgeden önce gelir; Tayvan, Hong Kong ve Makao varsayılan olarak geleneksel Çince kullanır. Portekizce Brezilya çevirisine eşlenir. Desteklenmeyen tercihlerde listedeki sonraki desteklenen dil, hiçbiri yoksa İngilizce kullanılır.

Arayüz ve yayın uzantısı aynı çevirileri kullanır. Sistem satın alma, ReplayKit ve yerel oynatıcı denetimlerinin dili iOS tarafından yönetilir. Hukuki belgeler ve yardım içeriği Türkçe/İngilizce sunulur; belge görünümünde dil seçimi vardır. Arayüz dili, cihazın SpeechAnalyzer konuşma dili desteği anlamına gelmez.

Metinler Humanizer yönergeleriyle kısa ve doğal tutuldu. Marka ve teknik biçim adları çevrilmez. Bağımsız ana dil editörü incelemesi yapılmadı.

## Doğrulama

16 dilin her birinde 183 uygulama metni ve yerel ağ izin açıklaması bulunur. CarPlay Audio çalışmasıyla Şu An Çalıyor etiketi mevcut 16 dile eklendi; yeni dil eklenmedi. Eksik anahtar ve biçim parametresi kontrolleri geçti. Arapça, İbranice, Tayca, Vietnamca, Endonezce ve Hintçe uygulama paketinde bulunmaz. Derleme ve testlerin güncel sonuçları `docs/IMPLEMENTATION_STATUS.md` içindedir.

16 dilde açılış, dil arama/değiştirme, seçimi yeniden açılışta koruma ve sistem diline dönüş testleri geçti. Sonradan yapılan belge bağlantısı/yerel dil seçimi eşleştirmesinin ekran kontrolü açık kaldı: son simülatör denemelerinde dokunmalar belge ekranına ulaşmadan sonuç vermedi. Bu son değişiklik yalnızca derleme düzeyinde doğrulandı. Ayrıntılı kanıtlar `docs/IMPLEMENTATION_STATUS.md` içindedir.
