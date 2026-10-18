> 18 Ekim 2026 güncellemesi: Aşağıdaki güncel App Review denetimi esas alınır. Eski build, gizlilik yayını, ürün ve sözleşme kayıtları tarihseldir; güncel dağıtım kanıtı DEPLOYMENT.md içindedir.

# Mirivo 1.0 kabul kaydı

## 18 Ekim 2026 — App Review öncesi canlı kontrol

App Store Connect'te 1.0 sürümü `Developer Rejected`, seçili ikili hâlâ **14**; son gözlenen TestFlight sürümü **35 / Testing**. İnceleme taslağında Mirivo Pro grubu ile haftalık/yıllık abonelikler bulunuyor, uygulama sürümü henüz eklenmemiş. Portal bu nedenle gönderimi engelliyor. Son aday Apple'a yüklendikten sonra seçilmeli ve uygulama sürümü aynı taslağa eklenmeli. Bu denetimde Apple'a ikili yükleme veya App Review gönderimi yapılmadı.

İki abonelik de `Ready for Review`; ülkeler/bölgeler seçili ve inceleme görselleri mevcut. Free Apps Agreement, Paid Apps Agreement, banka hesabı, ABD vergi belgeleri ve DSA canlı kontrolde `Active`. İnceleme iletişim alanları dolu, giriş hesabı gerekmiyor, yayın tercihi manuel. Yaş derecesi alanları doldurulmuş. Gizlilik beyanı yayımlanmış; 18 Ekim gizlilik metinleri, koşullar ve yardım bağlantıları HTTPS 200 döndü. İnceleme notlarındaki Apple örnek HLS bağlantısının ana ve alt listeleri de 200 döndü; bu kontrol fiziksel oynatma kanıtı değildir.

Portal inceleme notlarında artık desteklenmeyen ömür boyu ürünü geri yükleme anlatımı bulunuyor. `Release/AppStore/review-notes.txt` haftalık/yıllık ürünler, bağımsız ve varsayılan kapalı ölçümleme/çökme izinleri ve StoreKit puanlama davranışıyla güncellendi; portala henüz uygulanmadı.

Content Rights alanında “No, this app does not contain, show, or access third-party content.” seçili. Bu ifade kullanıcı kaynaklarıyla IPTV/M3U/Xtream oynatma işleviyle uyuşmuyor. Hesap sahibi uygulanabilir içerik haklarını/izinlerini değerlendirip beyanı düzeltmeli; bu denetim içerik lisansı onayı vermedi ve alanı değiştirmedi. [Apple alan açıklaması](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).

Kullanıcı bu görüşmede gerçek araçta video, iPhone kilitliyken yeni kaynak açma ve park → sürüş → park geçişlerini **henüz doğrulamadığını** bildirdi. Ayrıca yalnız RevenueCat ücretsiz Pro erişimini doğruladı; Apple sandbox üzerinden haftalık/yıllık deneme satın alma ve geri yükleme kabulü açık. Yerel StoreKit testleri ve ücretsiz Pro hakkı bu ödeme kabulünün yerine geçmez. [Apple satın alma inceleme hazırlığı](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases).

18 Ekim devam kontrolünde diğer çalışmanın tamamlanmış kayıtları da incelendi. Build 38 ve fiziksel iPhone ile Mac'teki CarPlay Simulator menüleri açılmış; video testinde iki kez AVFoundation `-11870` (`AVErrorExternalPlaybackNotSupportedForAsset`) oluşmuş. Bu, gerçek araç testi değildir ve kullanıcı/sağlayıcı medyasında aynı sonucun oluşacağını kanıtlamaz; yine de video çıkışı için açık bir başarısızlık olarak değerlendirilmelidir. Kaynak: `docs/VEHICLE_PLAYBACK_QA.md`, `build/performance-audit-20261018/verification-summary.json` ve ilgili cihaz günlüğü. Aynı denetimin 16 UI senaryosu ve 18 seçili fiziksel cihaz testi için geçen sonuçları, bu açık video sorununu kapatmaz.

Üretim Release **1.0 (39)** arşivi, App Store IPA imzası ve otomatik Crashlytics sembol yüklemesi tamamlandı. Uygulama/uzantı dSYM UUID'leri son IPA ile eşleşiyor. Üretim dSYM'sinde `AppMeasurement.swift:55` yerel olarak çözüldü; bu adayda üretim çökmesi oluşturulmadı. 29 dağıtım ve 77 Swift Core testi geçti; bir isteğe bağlı test atlandı. Apple'a ikili yükleme veya inceleme gönderimi yapılmadı. Mac kilitli olduğu için bu devam turunda portal yeniden görüntülenemedi; yukarıdaki portal durumları aynı günün önceki canlı kontrolüne aittir.

Canlı kontrol kaydı: `Release/AppStore/readiness-20261018.json`. Üretim arşivi, IPA ve yükleme kanıtı: `Release/AppStore/release-archive-20261018.json`. Önceki Firebase panelinde kaynak satırı çözümleme kanıtı: `Release/AppStore/crashlytics-verification-20261018.json` (Debug/simülatör 1.0 (35)).

## 15 Ekim 2026 — indirme ve oynatıcı yön geçişleri

İndirme denetimi oynat düğmesinin soluna alındı; bütün indirme durumları aynı 58 puanlık alanı kullanır. Böylece durum metni görünürken başlık ve oynat düğmesi yer değiştirmez.

Tam ekrandaki TV seçicinin sunumu gizlenen araç çubuğundan kalıcı oynatıcı katmanına taşındı. Seçici açıkken kontrollerin gizlenme sayacı durur; cihaz aramasının 10 saniyelik sınırı kaldırıldı. Kullanıcı kapatana kadar arama ekranı açık kalır.

Tam ekrandan elle çıkış tercihi mevcut oynatıcı ziyaretinde korunur; geri çıkıp tekrar açınca otomatik yatay tam ekran yeniden etkinleşir. Durdururken yön politikası önce dikeye alınır ve kapanmakta olan oynatıcının gecikmiş yön olaylarının yatayı tekrar açması engellenir.

`testPlayerTVPickerAndManualFullscreenExitPersist` iOS 26.5 / iPhone 17 Pro Max simülatöründe geçti: TV seçici 12 saniye boyunca açık, hareketle çıkış sonrasında tekrar çevirme dikey görünümü koruyor, geri çıkıp tekrar giriş yatayı açıyor, durdurma sonrasında kaynaklar ekranı dikey kalıyor. Kayıt: `build/ui-audit/player-regressions-r3.log`; üç ekran görüntüsü aynı dizinde `mirivo-*.png`. Son kaynak koduyla `testOfflineDownloadPlaybackAndRemoval` ve `testPlayerModesGesturesAndControlLayout` da geçti (2/2, `build/ui-audit/player-regressions-final.log`). Toplam üç hedefli UI testi başarılı; `git diff --check` temiz. Fiziksel iPhone'daki geçiş animasyonunun görsel kabulü henüz yapılmadı.

## 15 Ekim 2026 — uygulama ekran denetimi

App Store Connect ve Developer portalı bu ekran denetiminde kullanılmadı. Denetim iOS 26.5 / iPhone 17 Pro Max simülatöründe, yerel sentetik medya ve StoreKit test ürünleriyle yapıldı.

İncelenen akışlar: Yansıt/Kaynaklar ana ekranları; kaynak ekleme türleri ve sistem dosya seçici; IPTV kategori/kanal listeleri ve hesap bitiş durumları; İzlemeye devam et listesi, arama, silme ve yeniden başlatma; indirme/çevrimdışı oynatma; oynatıcı, ses/altyazı seçimi, tam ekran, büyük kontroller ve hareket tanıtımı; bağlantı yapıştırma, fotoğraf seçimi ve slayt editörü; Cast/AirPlay/CarPlay rehberleri ve bağlantı durumu; ayarlar, dil araması/kalıcılığı, bildirimler, canlı altyazı düzeni, üçüncü taraf lisansları, geliştirme bağlantı testi, Pro planları ve zorunlu güncelleme.

Düzeltmeler:

- CarPlay bağlantısı kendi adı ve araç simgesiyle gösterilir; video desteklemeyen araçta açık durum metni bulunur. Bağlantı penceresi büyük yazıda tam yükseklikte açılır ve kaydırılabilir.
- Pro plan açıklaması ve fiyatı erişilebilirlik yazı boyutlarında alt alta yerleşir; daralan açıklamaların harf harf bölünmesi giderildi.
- Oynatıcı tam ekrandan çıkış düğmesinin etiketi mevcut eylemi anlatır.
- HTTP indirme hataları sabit çeviri anahtarları ve durum kodu biçimlendirmesi kullanır. Dört yeni metin 22 dile eklendi; yayın kontrolü interpolasyon içeren çeviri anahtarlarını hata sayar.
- Eski tam ekran kapatma/yerleşik web görünümü beklentileri güncel akışa uyarlandı. İndirme satırı, menü animasyonu ve hareket tanıtımı için UI testleri doğru denetimi ve hazır durumu bekler. Xcode'un test sonrasında takılan ayrıntılı tanılama toplaması kapatıldı; sonuç paketi ve ekran görüntüleri korunur.

Hedefli tekrarlar sonunda 22 UI testi ve 2 uygulama testi geçti. Oynatma listesinde arama/kanal değiştirme ve ayarlar/Pro üzerinden Türkçe-İngilizce gizlilik, koşullar ve yardım sayfalarını Safari'de açma da doğrulandı. İlk geniş koşu testleri bitirdikten sonra Xcode'un ayrıntılı tanılama toplaması takıldığı için durduruldu; o koşunun logu ve ekran görüntüleri korundu, başarısız testler düzeltmelerden sonra tekrar çalıştırıldı. `build/ui-audit/test-status.json` her testin en son sonucunu ve ilgili logunu gösterir; tamamlanan sonraki koşuların `.xcresult` paketleri de saklandı.

Yerel kanıtlar `build/ui-audit/` altındadır. Statik kontrol: 22 dil, 331 anahtar, 7.282 değer, sıfır hata. Dağıtım betiği testleri: 25/25 geçti. Fiziksel araç/TV görüntüsü, canlı satın alma, konuşma tanıma modelinin indirilmesi ve gerçek yayın sırasındaki altyazı bu simülatör denetiminin kapsamında doğrulanmadı.

Denetimden sonra son kaynak kodundan imzalı Debug 1.0 (8) derlendi; mevcut geliştirme profiliyle iPhone 16 Pro'ya yerel ağdan kurulum ve başlatma başarılı. Profil güncellemesi veya mağazaya yükleme yapılmadı. Kurulum ve başlatma kayıtları `build/ui-audit/install.json` ve `launch.json` içindedir; bu adım telefondaki bütün ekranların veya gerçek araç çıkışının fiziksel kabulü sayılmaz.

Bu dosya testlerin yerine geçmez. Tamamlanmış yerel doğrulamaların çıktıları IMPLEMENTATION_STATUS.md içinde listelenir. Aşağıdaki fiziksel ölçümler şu anda elde edilmedi.

## Fiziksel cihaz ve araç

15 Ekim boş ekran incelemesi: kullanıcı Kia EV6'da Mirivo simgesini açınca içerik alanının boş kaldığını yeniden bildirdi. Telefonda bugüne ait çökme raporu ve alınan uygulama tanılamasında CarPlay bağlantı olayı bulunmadı; bu bulgular tek başına nedeni kanıtlamaz. App delegate CarPlay ve harici ekran rollerini açıkça ilgili scene delegate'e yönlendirir; telefon sahnesi SwiftUI'ya bırakılır. Sahne isteği ve kök şablon kurulumu için tanılama olayları eklendi. İlk denemede yakalanan SwiftUI sahne geri yükleme özyinelemesi düzeltildi; `testAccessoryScenesUseTheirOwnDelegatesAndLeavePhoneToSwiftUI` simülatörde geçti (`build/deploy/carplay-scene-tests-r2.log`). Eski kaydedilmiş sahne yalnız telefona aittir; CarPlay sorununun nedeni olarak kabul edilmedi. Kullanıcı araçtan ayrıldığı için bu değişikliğin gerçek araçta boş ekranı giderdiği henüz doğrulanmadı.

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
