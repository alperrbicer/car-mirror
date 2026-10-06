# Mirivo ürün ve uygulama planı

Bu planın amacı, ilk sürümden itibaren App Store'da yayımlanacak; iPhone ekranını CarPlay'e yansıtan, sesiyle birlikte kullanılabilir ve görsel açıdan tamamlanmış bir ürün teslim etmektir. İlk fiziksel kabul ortamı kullanıcının iPhone 16 Pro telefonu ve 2024 Kia EV6 aracının orijinal ekranıdır. Bitmiş ürün ölçütü gerçek araçtaki sonuç ve mağazada yayımlanmış sürümdür. Derlenmesi, telefona kurulması veya ekran yakalamanın başlaması tek başına tamamlanma sayılmaz.

Plan tarihi: 2 Ekim 2026. İlk uygulama çalışması başladı: oturum durumu, tanılama, araç çıkışını ölçen test araçları ve koyu arayüz uygulandı. Gerçek araç görüntüsü henüz doğrulanmadı. Bu belgedeki kabul hedefleri ölçülmüş sonuç değildir; güncel kanıtlar [uygulama durumu](IMPLEMENTATION_STATUS.md) belgesindedir.

## Başlangıç kararları

Kullanıcının kesinleştirdiği kapsam:

- İlk sürüm App Store yayını içindir. Geliştirme ve dağıtım yetkileri, TestFlight, mağaza içerikleri ve App Review süreci baştan kapsamdadır.
- İlk kabul ortamı iPhone 16 Pro ve 2024 Kia EV6'dır. Testteki iOS sürümü, araç yazılımı ve bağlantı biçimi kaydedilir.
- YouTube ve **Smarters Player** ana kullanım senaryolarıdır. Hesap ve yayın adresleri tanılama raporlarına eklenmez.
- Kullanıcı hem doğrudan kabloyla hem Çin'den aldığı markasız kablosuz CarPlay adaptörüyle bağlanıyor. İlk karşılaştırma kablolu bağlantıyla, ardından aynı uygulama sürümüyle adaptör üzerinden yapılır. CarTV'nin iki bağlantıda da aynı sonuçla çalıştığı henüz ayrı ayrı doğrulanmadı.
- Kullanıcı 2 Ekim 2026'da **Mirivo + A (grafit/mint)** seçimini yaptı. Görünen adlar ve marka varlıkları Mirivo olarak uygulanır. Mevcut Apple uygulama kimlikleri, App Group ve Xcode hedefleri korunur.
- Görsel yön sade, premium ve koyudur: A yönünün grafit/mint renkleri korunur. Kullanıcı, 2 Ekim 2026'da iki ekranın önündeki çerçeveye otomobil eklenen logoyu seçti.
- Hem logo hem teknik hata ve bağlantı kayıtları ilk sürüm kapsamındadır.

Kapsamı değiştiren bir karar sessizce uygulanmaz; karar ve etkisi bu belgeye işlenir. Günlük kod ve tasarım ayrıntıları için tekrar tekrar onay istenmez.

Kullanıcı, Mirivo + A uygulandıktan sonra 2 Ekim 2026'da **“chrome işlerini de yap”** talimatıyla Chrome aşamasını başlattı. Önceki bekleme talimatı kalktı. Apple portalı, yetki başvuruları, uygulama kaydı ve uygun profil varsa imzalı kurulum bu aşamanın kapsamındadır. Yeni bir sözleşme kabulü istenirse son kabul adımında ayrıca onay alınır.

Önerilen ilk kullanım akışı: kullanıcı araç ekranında uygulama simgesini açar; gerekli ekran yayını onayını telefondaki sistem akışında verir; YouTube veya IPTV uygulamasına geçer; görüntü ve ses araçta devam eder. Durdurma ve yeniden başlatma, kullanıcıyı yeniden kurulum yapmaya zorlamaz. Bu akış gerçek araç çıkışı ve iOS'un sunduğu kontrollerle doğrulanır.

Son kullanıcı kararları: Pro altyapısı hazırlanacak, satış daha sonra açılacak; mevcut sürüm reklamsız; gelecekteki tüm sürümler için reklam taahhüdü verilmez. İlk sürümde mevcut özellikler açık. Yıllık ve tek ödemelik ürünler için gerçek fiyat/ülke kararları satış öncesinde verilecek. Destek adresi alperrbicer@gmail.com, yayıncı Alper Biçer. Türkçe/İngilizce arayüz, mağaza metinleri ve Netlify üzerinden açılan yasal ve destek sayfaları hazırlandı. Kullanıcının 3 Ekim 2026 talimatıyla Arapça, İbranice, Tayca, Vietnamca, Endonezce ve Hintçe eklendi; dil kapsamı 22 oldu. Ayrıntı docs/LOCALIZATION.md dosyasında. Netlify dağıtımı 5 Ekim 2026’da güncellendi; uygulama doğrudan yayımlanmış belgelere yönlenir.

## Mevcut durum ve açık sorular

| Konu | Eldeki bilgi | Tamamlanması gereken |
| --- | --- | --- |
| Referans deneyim | Kullanıcı CarTV'yi aynı araçta kendi CarPlay simgesinden açarak yansıtabiliyor. | Aynı bağlantı biçimini ve kaynak uygulamaları kaydetmek, başlangıç süresini ve gecikmeyi ölçmek. |
| CarTV yetkileri | Telefonda kurulu sürümde CarPlay Audio ve Video yetkileri görüldü. | Yetkilerden bağımsız olarak görüntünün hangi çıkış yoluyla taşındığını belirlemek. |
| CarTV sahneleri | CarPlay sahnesi ve iki harici ekran rolü kurulum bildiriminde var. | Bu harici ekranların EV6 üzerindeki yansıtmayla ilişkisini doğrulamak. Bildirim tek başına bunu kanıtlamıyor. |
| Apple başvurusu | Kullanıcının paylaştığı Apple e-postası Audio yetkisinin hesaba tanımlandığını doğruluyor. Video için yalnız önceki başvuru alındı bilgisi mevcut. | App ID, geliştirme/dağıtım profilleri ve gerçek imzadaki Audio yetkisini doğrulamak; Video sonucunu ayrıca takip etmek. |
| İmzalama | Varsayılan Audio; açık `--carplay-video` seçimi Audio + Video ister. Çalışma zamanı, imza ve profil kontrolleri seçilen moda göre ayrıldı. | İmzalı Audio sürümünde CarPlay simgesi ve kaynak sesi; Video yetkisi sonrası yansıtma için gerçek araç kabulünü tamamlamak. |
| Yakalama | ReplayKit uzantısında H.264/AAC, iki kalite seçeneği ve cihaz içi canlı altyazı yolu mevcut. | Gerçek uygulamalar arasında geçiş, uzun kullanım, duraklama ve yeniden başlatmayı doğrulamak. |
| Araç çıkışı | Kod, video destek bildirimi ve yerel ağ adresi üzerinden oynatmaya dayanıyor. | EV6'da gerçekten çalışan görüntü yolunu kurmak. Mevcut yöntem henüz doğrulanmış değil. |
| Ses | ReplayKit uygulama sesi AAC olarak video ile aynı zaman tabanına kodlanıyor; yerel çözüm ve zaman çizgisi testi geçti. | Fiziksel CarPlay rotası, çift ses ve kaynak uygulama davranışı ile gerçek gecikmeyi ölçmek. |
| Tasarım | Mirivo + A seçildi; görünen adlar, logo, üç ikon görünümü, destek alanı ve kısa açılış geçişi uygulandı. | Güncel markanın fiziksel iPhone ve CarPlay üzerinde incelenmesi. |
| Loglar | Ana uygulama ve uzantı için türleri sınırlandırılmış, oturum bazlı JSON kayıtları ve rapor paylaşımı eklendi. | Gerçek araç kaydını değerlendirmek; telefonda sistem paylaşım ekranını uçtan uca doğrulamak. |
| Kurulum araçları | Depoda cihaz, simülatör, arşiv ve yükleme komutları bulunuyor. | Mevcut komutları geliştirme ve teslim sürecine bağlamak; seçilen son yetkilerle doğrulamak. |
| Mağaza hazırlığı | Mirivo App Store Connect kaydı oluşturuldu: Apple ID `6818560405`, Türkçe ana dil, SKU `mirivo-ios`, mevcut bundle kimliği. İlk iOS 1.0 kaydı `Prepare for Submission`. | Dağıtım profili, test edilmiş Release sürümü, ürün sayfası, TestFlight ve inceleme paketini tamamlamak. |

Apple, video yetkisiyle görünürlüğü aracın video desteğine bağlıyor; uygun Audio ve Video yetkilerini birlikte kullanan uygulamalar için görünürlük daha geniş. Bu açıklama, EV6'da görüntü aktarımının çalışacağını tek başına göstermiyor. [Apple CarPlay oturumu](https://developer.apple.com/videos/play/wwdc2026/212/)

**En önemli teknik karar:** EV6'da kullanılabilir görüntü çıkışı bulunmadan aktarım mimarisi kesinleştirilmeyecek. CarTV'nin çalışması hedefi destekleyen bir bulgudur; onun iç uygulamasını bildiğimiz anlamına gelmez.

App Store hedefi mimari kararın bir parçasıdır: kullanılacak API'ler, talep edilen CarPlay kategorisi ve gerçek yansıtma işlevi birbiriyle uyumlu olmalıdır. Apple, herkese açık API'lerin amaçlarına uygun kullanılmasını istiyor. Bu nedenle yetki onayı, çalışan aktarım ve App Review kabulü ayrı sonuçlar olarak izlenir. [App Review 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

Resmî CarPlay video akışının ürün kapsamı, destekleyen araçlarda park hâlinde kullanımdır. Video kullanılabilirliği değiştiğinde oynatma ve arayüz sistemin bildirdiği duruma uyarlanır. [Apple CarPlay](https://developer.apple.com/carplay/)

## İşlerin sırası

Teknik çalışma ile marka ve arayüz tasarımı birlikte ilerler. Loglama ilk araç testinden önce hazırlanır. Nihai arayüzün çalışan oturuma bağlanması, araç çıkışının doğrulanmasına bağlıdır.

| Aşama | Yapılacak iş | Çıktı | Aşamayı kapatma ölçütü |
| --- | --- | --- | --- |
| 1 | Kullanım senaryosunu, mağaza kapsamını ve mevcut kanıtları sabitlemek | Gereksinimler, referans test, açık karar listesi | Telefon, araç, bağlantı, kaynak uygulamalar ve başarı ölçütleri belirli |
| 2 | Yetkileri, yayımlanabilir mimariyi ve gerçek araç görüntü çıkışını doğrulamak | İmzalı uygulama, API/yetki kararı, araç bağlantı kaydı, hareketli test görüntüsü | CarPlay simgesi açılıyor ve değişen görüntü fiziksel EV6 ekranında görülüyor; dağıtım yetkilerinin durumu belirli |
| 3 | Ekran yakalama, ses ve oturum yönetimini tamamlamak | Kaynak uygulamalarla çalışan aktarım | YouTube ve seçilen IPTV uygulaması görüntü ve sesle çalışıyor; uygulama geçişinde sürüyor |
| 4 | İsim, logo ve görsel sistemi tasarlamak | İsim seçenekleri, iki tasarım yönü, seçilen marka seti | İsim ve görsel yön seçilmiş; temel ekran durumlarının tasarımı tamam |
| 5 | Tasarımı gerçek davranışlarla birleştirmek | iPhone ve CarPlay arayüzü, açılış deneyimi, hata ve yeniden bağlanma akışları | Her görünen durum gerçek oturum durumuyla tutarlı ve fiziksel cihazda incelenmiş |
| 6 | Dayanıklılık ve kullanıcı kabul testlerini bitirmek | Ölçümler, hata düzeltmeleri, test raporu | Aşağıdaki kabul senaryoları aynı teslim sürümünde geçiyor |
| 7 | TestFlight ve mağaza paketini tamamlamak | Dağıtım imzalı sürüm, ürün sayfası, gizlilik ve destek sayfaları, inceleme notları | TestFlight'tan kurulan aday sürüm telefonda ve EV6'da kabul testini geçiyor |
| 8 | App Review ve yayını tamamlamak | Onaylanan mağaza sürümü, eşleştirilmiş kaynak etiketi, test raporu ve kullanım notları | Uygulama mağazada erişilebilir; mağazadan kurulumu ve temel araç akışı doğrulanmış |

4. aşama, 1. aşamadan sonra 2. ve 3. aşamalarla birlikte yürütülebilir. 6. aşamanın testleri erken yazılır ve çalışma ilerledikçe uygulanır; sona bırakılmaz.

## Gerçek araçta aktarımı doğrulama

İlk teknik test, kullanıcıyı bütün ürünü tekrar tekrar denemeye göndermeden tek soruyu cevaplar: imzalı uygulamadan EV6 ekranına hareketli görüntü ulaştırabiliyor muyuz?

1. CarTV'nin çalıştığı düzen kaydedilir: kablo veya kablosuz bağlantı, varsa adaptör, telefonun iOS sürümü ve araç yazılımı. Kaynak video için hücresel internet kullanımı ile telefonun CarPlay bağlantısı birbirinden ayrılır.
2. Apple sonucunda verilen geliştirme ve dağıtım yetkileri kontrol edilir. Video başvurusunun Audio'yu kapsadığı varsayılmaz. Gerekli ayrı talep varsa ürünün gerçek işlevini anlatan içeriği hazırlanır. App ID, ana uygulama ve uzantı profilleri, App Group ve gerçek kod imzası eşleştirilir.
3. CarPlay sahnesinin açılışı, iOS'un verdiği ekran rolleri, video destek bildirimi ve kullanılabilir oynatma rotası kayda alınır.
4. Sabit bir başarı yazısı yerine sürekli değişen sayaç veya test deseni araçta gösterilir. Böylece yanlış ekran, donmuş kare ve sahte “bağlandı” durumları ayırt edilir.
5. Belgelenmiş CarPlay video yolu ile gerçekten sağlanan harici ekran sahnesi olasılığı değerlendirilir. Harici ekran tanımının varlığı, erişilebilir bir araç penceresi varmış gibi kullanılmaz.
6. Sonuç cihaz kaydı ve araç ekranındaki gözlemle birlikte saklanır. Test başarısızsa hangi adımda kesildiği belirlenir; çalışan araç çıkışı bulunmuş gibi medya ve ürün teslimine geçilmez.

Mevcut HLS ve yerel ağ yapısı bu testin sonucuna göre korunur, uyarlanır veya değiştirilir. Wi-Fi ağına bağlı olmayı gerektiren bir çözüm, kullanıcının mevcut CarTV deneyimiyle eşdeğer sayılmadan önce aynı koşullarda sınanır. Kullanıcıyı başka bir alıcıya, web sayfasına veya farklı donanıma yönlendirmek hedef değişikliğidir.

## Görüntü ve ses mimarisi

Araç çıkışı kanıtlandıktan sonra sorumluluklar netleştirilir: ekran yakalama, kodlama ve aktarım, araçta sunum, ses rotası, oturum yönetimi ve tanılama. Ana ekran bu teknik bileşenleri doğrudan yönetmez; tek bir oturum yöneticisinin durumunu gösterir.

ReplayKit mevcut başlangıç noktasıdır. Desteklenecek iOS aralığı belirlendiğinde yakalama API'si ve kullanılabilirlik kontrolleri yeniden değerlendirilir. Sadece minimum sürüm ayarının iOS 18 olması, o sürümde ürünün çalıştığı kabulünü doğurmaz.

Dengeli 960 × 540 / 20 fps ve yüksek 1280 × 720 / 30 fps seçenekleri uygulandı. Nihai kalite kabulü araç ve cihaz ölçümlerine bağlıdır. Aracın gerçek CarPlay görüntü alanı ölçülür; en boy oranı korunur, yatay ve dikey dönüşler işlenir, uygun çözünürlük ve kare hızı cihazın ısı ve bellek davranışıyla birlikte seçilir. Taşıma yolu belli olmadan HLS gecikmesini birkaç ayarla çözeceğimiz varsayılmaz.

Ses için iki yol ölçülür: kaynak uygulamanın mevcut CarPlay sesini koruyarak görüntüyü yeterince düşük gecikmeyle sunmak veya uygun olduğunda yakalanan uygulama sesini görüntüyle birlikte taşımak. İkinci yolun kaynak uygulamayı durdurmadığı ve çift ses üretmediği doğrulanır. Seçilen yöntem aynı zaman tabanında ölçülür. Kaynak sesin araçtan gelmesi, görüntüyle senkron olduğu anlamına gelmez.

Bağlantı, yakalama, oynatma ve ses ayrı durumlar olarak tutulur. Eski oturumdan gelen geç bildirimler yeni oturumu etkileyemez. Durdurma, iptal, yeniden deneme ve bağlantı kesilmesi bütün bileşenleri tutarlı şekilde sonlandırır. Yeniden bağlanmada iOS'un istediği yeni ekran paylaşımı onayı varsa kullanıcıya gerçek sistem akışı açılır.

## İsim ve görsel kimlik

Kullanıcının kararı **Mirivo + A (grafit/mint)**. [Seçilen görsel kimlik](../Design/mirivo.html) logo, ikon, renkler, açılış ve uygulama görünümünü bir araya getirir. Önceki [tasarım karşılaştırması](../Design/brand-directions.html) kararın geçmişi olarak korunur. 2 Ekim 2026'da [Mirivo App Store Connect kaydı](https://appstoreconnect.apple.com/apps/6818560405/distribution/info) oluşturuldu. Bu kayıt adın Apple tarafından kabul edildiğini gösterir; marka tescili veya hukuki marka uygunluğu araştırması yapılmış değildir.

Üç isim adayı karşılaştırıldı ve Mirivo seçildi. App Store Connect kaydı Türkçe ana dil ve `com.alperbicer.carmirror` bundle kimliğiyle açıldı.

İki görsel yön aynı ekranlar üzerinde karşılaştırıldı. Seçilen A yönünde grafit zemin (#090B0D), mint vurgu (#66E3C7), yuvarlak yazı karakteri ve ön çerçevesinde otomobil bulunan iki ekran logosu kullanılır. Kullanıcı, [araç vurgusu karşılaştırmasında](../Design/mirivo-vehicle-directions.html) otomobilli seçeneği tercih etti. Ana ekran, destek alanı, ikonlar ve açılış aynı görsel sistemi izler.

Marka teslimi; ana logo, yazı ile birlikte kullanım, küçük boyuta uygun uygulama simgesi, renk ve tipografi değerleri, hareket kuralları ve dışa aktarılmış varlıkları içerir. İkon iPhone ana ekranında ve araç uygulama ızgarasında okunaklı olmalıdır. Güncel iOS ikon görünümlerinde aynı temel şekil korunur; katmanlı varlıklar Icon Composer ile değerlendirilir. [Apple ikon rehberi](https://developer.apple.com/design/human-interface-guidelines/app-icons/)

Mirivo adı kaynakta telefon başlığına, CarPlay başlığına, yayın uzantısına, Now Playing bilgisine, ikonlara ve destek ekranına uygulandı. Apple kimlikleri ve Xcode hedef adları kurulum sürekliliği için korunur.

## Arayüz ve açılış deneyimi

Ana ekran, mevcut bağlantıyı ve yapılabilecek bir sonraki işlemi hemen anlaşılır kılar. Bir ana eylem bulunur; paylaşım başladıktan sonra bu alan durdurma veya gerekli yeniden deneme eylemine dönüşür. Teknik açıklamalar ve sayaçlar ana ekranın parçası olmaz.

| Durum | Kullanıcının gördüğü | Temel davranış |
| --- | --- | --- |
| Araç bekleniyor | Kısa bağlantı durumu | Gerektiğinde tek cümlelik bağlanma yönlendirmesi |
| Paylaşıma hazır | Belirgin paylaşım eylemi | Gerçek iOS ekran yayını seçicisini açar |
| Başlatılıyor | Kısa ve sakin bir ilerleme durumu | İptal edilebilir; belirsiz süre dönen yükleme bırakılmaz |
| Yayın etkin | Oturumun aktif olduğunu gösteren sade görünüm | Durdurma her zaman erişilebilir |
| Bağlantı kesildi | Sorunu ve yapılacak işlemi kısa anlatan durum | Uygun olduğunda yeniden bağlanma veya yeniden paylaşma |
| Hata | Anlaşılır hata metni | Yeniden dene ve gerekirse destek raporu paylaş |

Ekran yakalamanın başlaması tek başına araçta görüntü gösterildiği mesajına dönüşmez. Arayüz, eldeki gerçek çıkış sinyallerinin desteklediği durumu kullanır. Fiziksel araç görüntüsünün kabul testi ayrıca tutulur.

CarPlay tarafı aracın ve kullanılan API'nin izin verdiği yerleşime göre tasarlanır. Telefon ekranındaki serbest tasarımın aynısının CarPlay'e taşınabileceği varsayılmaz. Kontroller büyük, kısa ve tutarlı olur; içerik okunurluğu dekorasyondan önce gelir.

Açılış iki bölüm olarak tasarlanır. Sistem launch screen'i ana ekranın zemin ve sabit düzeniyle uyumlu olur. Uygulama hazır olduğunda kısa bir marka geçişi kullanılabilir; yapay bekleme eklenmez ve düğmeler geciktirilmez. İlk açılışa özel marka sunumu gerekiyorsa kurulum akışına yerleştirilir. Böylece splash screen isteği hızlı açılışla birlikte karşılanır. [Apple açılış rehberi](https://developer.apple.com/design/human-interface-guidelines/launching)

Tasarım kontrolleri iPhone 16 Pro'da yatay ve dikey görünüm, büyük metin boyutları, VoiceOver, kontrast, hareketi azalt ayarı ve koyu arayüzün farklı ekran parlaklıklarında okunurluğunu içerir. Gerekli sistem izinleri kullanım anında istenir; her açılışta uzun bir bilgilendirme akışı gösterilmez.

İlk sürümün ekran envanteri: kısa ilk kullanım yönlendirmesi, duruma göre değişen ana ekran, iOS yayın seçicisine geçiş, gerekli CarPlay kontrolleri ve küçük bir ayarlar/destek alanı. Ayarlar; sürüm bilgisi, tanılama raporu, gizlilik ve destek bağlantılarını barındırır. Ücretlendirme kararı bir satın alma akışı gerektirirse bu da tasarım ve test kapsamına eklenir.

## Teknik kayıtlar ve destek

İlk araç testinden önce ana uygulama ve yayın uzantısına ortak oturum kimliğiyle kayıt eklenir. Kayıtlar; sahne bağlantısı, yakalamanın başlaması, ilk kare, kodlama durumu, tampon ve kare düşürme sayıları, oynatma rotası, ses değişiklikleri, kesintiler ve hataları kapsar. Gerçek araç ekranı için alıcıdan doğrulama alınamayan durumlar kayıtta açık kalır.

Önerilen saklama sınırı son 10 oturum ve en fazla 5 MiB'dir. Ekran görüntüsü, video veya ses içeriği; yayın URL'si, erişim anahtarı, IPTV hesabı ve benzeri hassas alanlar kayda alınmaz. Ana uygulama ve uzantının aynı dosyaya kontrolsüz yazması önlenir. Rapor uygulama ve build sürümünü içerir.

Ayarlar içindeki destek alanında “Tanılama raporunu paylaş” ve “Kayıtları temizle” bulunur. Paylaşım, kullanıcının açtığı sistem paylaşım ekranından yapılır. Günlükler otomatik olarak üçüncü tarafa gönderilmez.

Aktarım için oluşan geçici medya parçaları oturum sonunda temizlenir; çökme sonrasında kalan parçalar bir sonraki açılışta kaldırılır. Ağ aktarımı oturuma özgü erişimle sınırlandırılır ve durdurma sırasında erişim iptal edilir. Gizlilik beyanı gerçek veri akışı, saklama davranışı ve kullanılan bağımlılıklar denetlendikten sonra hazırlanır.

## Ölçülebilir kabul hedefleri

Aşağıdaki sayılar önerilen kalite hedefleridir; henüz ölçülmüş sonuç değildir. İlk araç ölçümüyle fizibilitesi değerlendirilir. Sağlanamayan bir hedef sessizce düşürülmez; nedeni ve ürün üzerindeki etkisi konuşularak karar kaydedilir.

| Ölçüm | Önerilen hedef | Nasıl doğrulanır |
| --- | --- | --- |
| Telefon uygulamasının açılışı | 10 soğuk açılışın her birinde ana eyleme en geç 2 saniyede erişim | iPhone 16 Pro üzerinde ölçüm |
| İlk araç karesi | Araç hazırken ve iOS paylaşım onayı/sayacı tamamlandıktan sonra en geç 5 saniye | Oturum kayıtları ile araçta görünen hareketli sayaç birlikte |
| Ekran gecikmesi | Tipik kullanımda 500 ms veya altında | Telefon ve araçtaki aynı sayaç görüntüsünü karşılaştırma; yalnız kodlayıcı süreleri yeterli değil |
| Ses ve görüntü farkı | 150 ms veya altında | Bilinen eşzamanlı görüntü/ses işareti olan test videosu |
| Akıcılık | Seçilen çözünürlükte 30 fps hedefi | Araç çıkışı gözlemi, düşen kare ölçümü, ısı ve bellek kaydı |
| Uzun kullanım | YouTube ve seçilen IPTV uygulamasında ayrı ayrı en az 30 dakika | Donma, beklenmedik durma, çift ses ve giderek artan gecikme olmaması |
| Başlatma ve durdurma | Art arda 10 başarılı döngü | Önceki yayın kalıntısı ve yeniden başlatmayı engelleyen durum olmaması |
| Durdurma | Kullanıcı durdurduktan sonra en geç 2 saniyede aktif aktarımın kesilmesi | Ana uygulama, uzantı, ses ve alıcı birlikte |

Sistem kaynaklı veya içerik korumasından kaynaklanan yakalama davranışları, bağlantı hatalarıyla karıştırılmaz. Desteklenen uygulama ve içerikler gerçek test sonuçlarıyla belirtilir; “her uygulama ve her video çalışır” iddiası kurulmaz.

## Test ve teslim matrisi

| Test katmanı | Kapsam | Kanıt |
| --- | --- | --- |
| Birim ve medya testleri | Oturum durumları, eski bildirimlerin reddi, yön dönüşü, durdurma, ses/görüntü zamanları, kayıtların hassas veri içermemesi | Test raporu |
| Kurulum testleri | Gereken yetkiler, App Group, ana uygulama ve uzantı kimlikleri, sürüm, profil ve doğru cihaz | Mevcut kurulum araçlarının doğrulama çıktısı |
| Simülatör | Ana ekran durumları, yerleşim, büyük yazı, tema ve açılış geçişleri | Arayüz görüntüleri; araç testi olarak sayılmaz |
| Fiziksel iPhone | Kurulum, görünür açılış, gerçek yayın seçicisi, uygulamalar arası geçiş, hata ve destek akışı | Aynı build için cihaz gözlemi ve oturum raporu |
| Kia EV6 | Simge ve açılış, test deseni, YouTube, IPTV, ses, yön değiştirme, bağlantı kesilmesi ve yeniden bağlanma | Gerçek araç gözlemi ve ölçümler |
| TestFlight | Dağıtım imzası, yayın uzantısı, CarPlay yetkileri, temiz kurulum ve sürüm güncelleme | Mağaza dağıtımına aday build ile aynı araç senaryolarının geçmesi |
| Son kabul | Bütün önemli senaryoların aynı sürümde yeniden kontrolü | Kullanıcı kabulü ve sürümlenmiş sonuç listesi |

Araç testleri üç odaklı oturumda planlanır: ilk görüntü yolunu kanıtlama, gerçek uygulamalarla görüntü/ses testi ve son sürüm kabulü. Hata bulunursa ilgili oturum tekrar edilir. Her testten önce hangi build'in kurulacağı ve hangi sonucun ölçüleceği belirli olur. Telefonun kilitlenmesi, arama veya ses kesintisi sonrasında uygulamanın tanımlı bir duruma dönmesi de sınanır; iOS'un izin vermediği yakalamanın kesintisiz sürdüğü varsayılmaz.

Son teslimde isim, ikon, açılış, ana ekran, CarPlay ekranı, hata akışları ve tanılama raporu tamamlanmış olmalıdır. Çalışan kaynak sürümü, build numarası ve kullanılan cihaz/araç koşulları eşleştirilir. Başarılı testten sonra yalnızca derlenmiş başka bir sürüm aynı kanıtla teslim edilmez.

Kia EV6 ilk kabul aracıdır. Mağazada ilan edilecek destek kapsamı ayrıca tanımlanır: minimum iOS sürümü, gerekli araç video özelliği ve doğrulanmış bağlantı biçimleri. Daha geniş uyumluluk iddiası, o kapsamdaki cihaz ve araçlarda test kanıtıyla desteklenir. Yerel ağ izninin reddi ve varsa ağ bağımlılıkları da kullanıcı akışı içinde sınanır.

## İlk sürümün App Store yayını

Mağaza hazırlığı isim ve teknik mimari seçimiyle birlikte başlar. Geliştirme profilinin çalışması dağıtım profilinin de hazır olduğunu göstermez. TestFlight kurulumu ayrı bir kabul adımıdır.

1. Seçilen marka ve gerçek destek kapsamıyla App Store Connect kaydı hazırlanır. Ad, alt başlık, açıklama, anahtar kelimeler, dil ve ülke tercihleri birbiriyle tutarlı tutulur.
2. Gizlilik politikası ve destek sayfası çalışan URL'lerde hazırlanır. Uygulama içinden erişimleri sağlanır. Veri kullanımı beyanları, yaş derecelendirmesi ve gereken ihracat/hesap alanları gerçek uygulamayla eşleştirilir.
3. Ekran görüntüleri teslim sürümünün gerçek arayüzünden üretilir. Araç uyumluluğu ve ekran yansıtma vaatleri test sonuçlarını aşmaz. Kullanılan medya ve marka varlıklarının hakları kontrol edilir.
4. Tek bir kaynak sürümünden Release arşivi alınır. Ana uygulama ve yayın uzantısının gerçek dağıtım imzaları, profilleri ve yetkileri doğrulanır; bu sürüm TestFlight'a yüklenir.
5. TestFlight'tan temiz kurulum ve önceki sürümden güncelleme denenir. Aynı build ile EV6'daki görüntü, ses, yeniden başlatma ve uzun kullanım testleri tamamlanır.
6. App Review için CarPlay bağlantı koşulları, ekran paylaşımını başlatma adımları, test içeriği ve araçta çalışan sürümün gösterimi hazırlanır. İnceleme ekibinin uygulamayı hangi donanım ve adımlarla deneyebileceği açıkça belirtilir.
7. İnceleme sonucu ele alınır; düzeltme gerekirse etkilenen kabul testleri yeni build'de tekrar edilir. Onaylanan sürüm yayımlanır ve mağazadan kurulumla temel akış son kez doğrulanır.

Apple inceleme öncesinde tamamlanmış işlevler, doğru mağaza bilgileri ve gerekli test erişimini bekliyor; gizlilik bağlantısı hem mağaza kaydında hem uygulamada bulunmalı. [App Review rehberi](https://developer.apple.com/app-store/review/guidelines/)

Yükleme, TestFlight dağıtımı, incelemeye gönderme ve mağazada yayımlanma ayrı durumlar olarak raporlanır. Son teslim; yayımlanan sürümün bağlantısını, build numarasını, kaynak sürümünü, doğrulanmış uyumluluk listesini ve test sonuçlarını içerir. Apple inceleme süresi ve sonucu takvimde dış bağımlılık olarak tutulur.

## Sonraki çalışma için başlangıç sırası

1. Bağlantı ve kaynak uygulama bilgileri alındı. Fiziksel testte araç yazılımı, doğrudan kablo/adaptör karşılaştırması ve kaynak içeriğin sonuçları kaydedilecek.
2. İlk tanılama, hareketli test videosu, gerçek harici sahneye bağlı test deseni, oturum durumu ve yerel kontroller hazır. Kayıt ve test adımları [uygulama durumu](IMPLEMENTATION_STATUS.md) belgesinde.
3. Chrome aşaması başladı; Apple portalındaki yetkiler ve Mirivo mağaza kaydı kontrol edildi. CarPlay yetkileri kullanılabilir olduğunda imzalı kurulum ve ilk araç görüntüsü testine geçmek. Seçilen Mirivo + A markasını aynı fiziksel iPhone/CarPlay sürümünde incelemek.
4. Kanıtlanan çıkış yoluna göre görüntü/ses uygulamasını tamamlamak; seçilen tasarımı bu gerçek davranışlara bağlamak.
5. Aynı teslim sürümünü fiziksel iPhone, TestFlight ve EV6 kabul testinden geçirmek.
6. Mağaza paketini tamamlayıp App Review ve yayın adımlarını sonuçlandırmak.

Kesin teslim tarihi, Apple'ın sonucu ve araç görüntü yolunun fizibilitesi belli olduktan sonra tahmin edilir. Her aşamanın sonunda yalnızca neyin değiştiği, hangi kanıtın elde edildiği ve hangi ölçütün açık kaldığı raporlanır.

## 3 Ekim 2026 — kişisel medya ve TV kullanım deneyimi

Kullanıcının verdiği [TV Cast 4K mağaza sayfası](https://apps.apple.com/tr/app/id6447613526?l=tr), açıklaması ve dört tanıtım ekranı incelendi. Uygulama yüklenip donanımda denenmedi. Mağazada genel puan gösterecek kadar değerlendirme yok; başarı veya bütün TV’lerle uyumluluk iddiası bu incelemeden çıkarılmadı.

Mirivo’ya alınan fikirler:

| İhtiyaç | Uygulanan akış |
| --- | --- |
| Kaynak URL’si olmadan kişisel içerik paylaşmak | Ana ekranda fotoğraf, video, müzik/dosya ve hızlı bağlantı kartları. Sistem fotoğraf seçicisi yalnız kullanıcının seçtiği içeriği verir. |
| Fotoğrafları birlikte izlemek | En fazla 20 fotoğrafı seçim sırasıyla, fotoğraf başına 3/5/8 saniye gösteren yerel 1080p H.264 slayt. Orijinaller değiştirilmez; fotoğraflar kırpılmadan sığdırılır. |
| Telefonda veya iCloud Drive’da bulunan medyayı açmak | Dosya seçimi, geçici yerel kopya, ortak oynatıcı, otomatik sıradaki dosya ve ses dosyası görünümü. TV’nin codec desteği ayrıca gerekir. |
| Tek seferlik bir yayını hızlı açmak | Kullanıcının yapıştırdığı doğrudan HTTP(S) medya adresini kaynak kaydetmeden oynatma. Web sayfasından video çıkarma veya DRM aşma içermez. |
| İlk bağlantıyı anlayabilmek | Google Cast, AirPlay ve CarPlay için ayrı rehber; cihaz bulunamadığında ağ/izin önerileri ve uygulama ayarlarına geçiş. |
| Aktarım sırasında ne olduğunu bilmek | Yerel dosya TV’ye aktarılırken iPhone’un açık kalması gerektiği belirtilir; aktarım ve tam ekran çakışınca ekran kilidi erken bırakılmaz. |

Google Cast’in yerel dosyaya erişimi, yalnız mevcut dosyayı rastgele oturum yolu üzerinden sunan geçici HTTP sunucusuyla sağlanır. HTTP Range ve HEAD desteklenir; dosyalar 64 KiB parçalarla okunur. Durdurma sunucuyu ve adresi kapatır. Kişisel medya adresleri kaynak Keychain’ine veya kalıcı oynatma geçmişine eklenmez. İptal edilen seçimler temizlenir; önceki oynatma sırasının kullanılmayan kopyaları yeni sırada, kalan geçici kopyalar sonraki uygulama açılışında kaldırılır.

Grafit/mint kimlik ve üst gezinme korundu. Yeni metinlerin 22 dilde karşılığı var. TV sesini kumandayla çift yönlü eşleme, DLNA, web tarayıcısından medya tespiti, kamera ve çizim tahtası bu değişiklikte uygulanmadı. Özellikle TV markası üzerinden doğrulanmamış uyumluluk veya 4K aktarım sözü eklenmedi. Fiziksel iPhone/TV/CarPlay kabulü ayrı kalır.
