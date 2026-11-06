# Mirivo App Store branding ve yerelleştirme: Aşama 2 onay raporu

Tarih: 6 Kasım 2026

## Durum ve kapsam

Bu rapor yerel taslakları kapsar. App Store Connect’te hiçbir alan değiştirilmedi veya kaydedilmedi. Yeni sürüm oluşturulmadı, App Review’a gönderim yapılmadı ve uygulama koduna dokunulmadı. Depodaki ilgisiz mevcut değişiklikler korundu.

Orijinal metadata yedeği: /private/tmp/mirivo-appstore-metadata-backup-2026-11-06.

## App Store Connect locale kontrolü — 6 Kasım son kontrolü

Yan sekmede iOS 1.0 sayfası açıldı. Sayfa **Ready for Distribution** gösteriyor; metadata alanları salt okunur ve Save düğmesi pasif. Locale seçicisinde aşağıdaki 22 dil listeleniyor ve depo klasörleriyle bire bir eşleşiyor. Türkçe canlı metinler açıldı; diğer 21 dilin alan içerikleri tek tek okunamadığı için metin eşleşmesi doğrulanmış sayılmıyor. App Store Connect’te değer karşılaştırma ve taslağı yükleme adımı, onaydan sonra yetkili kullanıcı tarafından her locale için yapılmalı.

| Locale | Dil | ASC locale listesinde | Depo klasörü |
|---|---|---:|---:|
| ar | Arapça | Evet | Eşleşti |
| de | Almanca | Evet | Eşleşti |
| en | İngilizce | Evet | Eşleşti |
| es | İspanyolca | Evet | Eşleşti |
| fr | Fransızca | Evet | Eşleşti |
| he | İbranice | Evet | Eşleşti |
| hi | Hintçe | Evet | Eşleşti |
| id | Endonezce | Evet | Eşleşti |
| it | İtalyanca | Evet | Eşleşti |
| ja | Japonca | Evet | Eşleşti |
| ko | Korece | Evet | Eşleşti |
| nl | Felemenkçe | Evet | Eşleşti |
| pl | Lehçe | Evet | Eşleşti |
| pt-BR | Brezilya Portekizcesi | Evet | Eşleşti |
| ru | Rusça | Evet | Eşleşti |
| sv | İsveççe | Evet | Eşleşti |
| th | Tayca | Evet | Eşleşti |
| tr | Türkçe | Evet | Eşleşti |
| uk | Ukraynaca | Evet | Eşleşti |
| vi | Vietnamca | Evet | Eşleşti |
| zh-Hans | Basitleştirilmiş Çince | Evet | Eşleşti |
| zh-Hant | Geleneksel Çince | Evet | Eşleşti |

## Eski ve yeni mağaza metinleri

Karakter sayısı Python Unicode code point sayısıdır. Keywords ayrıca UTF-8 bayt sayısıdır. Eski değerler yedek alınan yerel metadata’dan, yeni değerler mevcut yerel taslaklardan okundu; eski değerler App Store Connect’ten okunmadı.

### ar · Arapça

- App Name eski (6): Mirivo
- App Name yeni (19): Mirivo: IPTV ووسائط
- Subtitle eski (9): مشغل IPTV
- Subtitle yeni (28): للتلفاز، شاهد عند الوقوف فقط
- Promotional Text eski (147 karakter): اجمع IPTV ووسائطك. تابع من حيث توقفت، شاهد دون إنترنت، وانقل للتلفاز عبر Google Cast وAirPlay. شاهد عبر CarPlay المتوافق عندما تكون السيارة مركونة.
- Promotional Text yeni (134 karakter): مصادر IPTV ووسائطك الشخصية في مكان واحد. شاهد على هاتفك، وانقل إلى تلفاز متوافق، وشغّل الفيديو على شاشة سيارة مدعومة أثناء الوقوف فقط.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (50 karakter; 83 UTF-8 bayt): m3u,xtream,بث مباشر,أفلام,مسلسلات,راديو,مشغل فيديو
- Description eski: 2476 karakter; yeni: 2454 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### de · Almanca

- App Name eski (6): Mirivo
- App Name yeni (21): Mirivo: IPTV & Medien
- Subtitle eski (11): IPTV-Player
- Subtitle yeni (27): TV-Cast; Video nur im Stand
- Promotional Text eski (143 karakter): IPTV und Medien bündeln, weiterschauen, offline ansehen. Mit Google Cast und AirPlay zum TV; mit kompatiblem CarPlay im geparkten Auto schauen.
- Promotional Text yeni (155 karakter): Deine IPTV-Quellen und persönlichen Medien an einem Ort. Sieh auf dem iPhone, übertrage auf kompatible Fernseher und spiele Videos im Auto nur im Stand ab.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (71 karakter; 71 UTF-8 bayt): m3u,xtream,streaming,playlist,filme,serien,radio,offline,mediathek,cast
- Description eski: 3126 karakter; yeni: 3134 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### en · İngilizce

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV & Media
- Subtitle eski (11): IPTV Player
- Subtitle yeni (30): Cast to TV, Watch While Parked
- Promotional Text eski (146 karakter): IPTV and media in one place. Resume, watch offline, cast to TV with Google Cast and AirPlay, and watch on compatible CarPlay systems while parked.
- Promotional Text yeni (153 karakter): Your IPTV sources and personal media in one place. Watch on your phone, send to compatible TVs, and play video on supported vehicle screens while parked.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (71 karakter; 71 UTF-8 bayt): m3u,xtream,streaming,playlist,movies,series,radio,offline,video,library
- Description eski: 2877 karakter; yeni: 2835 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### es · İspanyolca

- App Name eski (6): Mirivo
- App Name yeni (21): Mirivo: IPTV y medios
- Subtitle eski (16): Reproductor IPTV
- Subtitle yeni (28): Envía a TV, mira solo parado
- Promotional Text eski (148 karakter): Tu IPTV y tus medios juntos. Retoma, mira sin conexión y envía a TV con Google Cast y AirPlay. Usa CarPlay compatible solo con el vehículo aparcado.
- Promotional Text yeni (159 karakter): Tus fuentes IPTV y tus medios personales, en un solo lugar. Mira en el móvil, envía a televisores compatibles y reproduce vídeo en el coche solo al estacionar.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (76 karakter; 78 UTF-8 bayt): m3u,xtream,streaming,lista,películas,series,radio,descargas,vídeo,biblioteca
- Description eski: 3167 karakter; yeni: 3209 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### fr · Fransızca

- App Name eski (6): Mirivo
- App Name yeni (23): Mirivo : IPTV et médias
- Subtitle eski (12): Lecteur IPTV
- Subtitle yeni (27): TV Cast; vidéo qu’à l’arrêt
- Promotional Text eski (145 karakter): IPTV et médias réunis. Reprenez, regardez hors ligne, diffusez sur TV avec Google Cast et AirPlay, ou via CarPlay compatible, véhicule stationné.
- Promotional Text yeni (162 karakter): Vos sources IPTV et vos médias personnels au même endroit. Regardez sur votre téléphone, diffusez vers une TV compatible et lisez des vidéos en voiture à l’arrêt.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (72 karakter; 74 UTF-8 bayt): m3u,xtream,streaming,playlist,films,séries,radio,hors ligne,bibliothèque
- Description eski: 3269 karakter; yeni: 3301 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### he · İbranice

- App Name eski (6): Mirivo
- App Name yeni (18): Mirivo: IPTV ומדיה
- Subtitle eski (8): נגן IPTV
- Subtitle yeni (29): לטלוויזיה, צפו רק כשהרכב חונה
- Promotional Text eski (137 karakter): IPTV ומדיה במקום אחד. ממשיכים מאותה נקודה, צופים אופליין ומשדרים לטלוויזיה עם Google Cast ו-AirPlay. צופים ב-CarPlay תואם רק כשהרכב חונה.
- Promotional Text yeni (114 karakter): מקורות ה-IPTV והמדיה האישית שלכם במקום אחד. צפו בטלפון, העבירו לטלוויזיה תואמת והפעילו וידאו ברכב כשהוא חונה בלבד.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (58 karakter; 97 UTF-8 bayt): m3u,xtream,שידור חי,סרטים,סדרות,רדיו,נגן וידאו,רשימה,הורדה
- Description eski: 2332 karakter; yeni: 2345 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### hi · Hintçe

- App Name eski (6): Mirivo
- App Name yeni (22): Mirivo: IPTV और मीडिया
- Subtitle eski (11): IPTV प्लेयर
- Subtitle yeni (29): TV पर भेजें, पार्क करके देखें
- Promotional Text eski (154 karakter): IPTV और मीडिया एक जगह। वहीं से देखें जहाँ छोड़ा था, ऑफ़लाइन देखें, Google Cast और AirPlay से TV पर भेजें। संगत CarPlay पर केवल पार्क की हुई कार में देखें।
- Promotional Text yeni (130 karakter): आपके IPTV स्रोत और निजी मीडिया एक जगह। फ़ोन पर देखें, संगत TV पर भेजें और समर्थित वाहन स्क्रीन पर वीडियो केवल पार्क होने पर चलाएँ।
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (31 karakter; 67 UTF-8 bayt): m3u,xtream,फ़िल्म,सीरीज़,रेडियो
- Description eski: 2748 karakter; yeni: 2727 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### id · Endonezce

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV & Media
- Subtitle eski (12): Pemutar IPTV
- Subtitle yeni (28): TV, tonton hanya saat parkir
- Promotional Text eski (151 karakter): IPTV dan media jadi satu. Lanjutkan, tonton offline, kirim ke TV via Google Cast dan AirPlay. Tonton lewat CarPlay yang kompatibel saat mobil diparkir.
- Promotional Text yeni (146 karakter): Sumber IPTV dan media pribadi Anda di satu tempat. Tonton di ponsel, kirim ke TV kompatibel, dan putar video di layar kendaraan hanya saat parkir.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (78 karakter; 78 UTF-8 bayt): m3u,xtream,streaming,daftar putar,film,serial,radio,offline,video,pustaka,cast
- Description eski: 2917 karakter; yeni: 2943 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### it · İtalyanca

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV e media
- Subtitle eski (12): Lettore IPTV
- Subtitle yeni (28): TV-Cast; video solo in sosta
- Promotional Text eski (147 karakter): IPTV e media insieme. Riprendi, guarda offline, trasmetti alla TV con Google Cast e AirPlay e usa CarPlay compatibile solo con l’auto parcheggiata.
- Promotional Text yeni (144 karakter): Le tue fonti IPTV e i tuoi media personali in un unico posto. Guarda sul telefono, invia alla TV e riproduci video in auto solo a veicolo fermo.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (68 karakter; 68 UTF-8 bayt): m3u,xtream,streaming,playlist,film,serie,radio,offline,libreria,cast
- Description eski: 3063 karakter; yeni: 3093 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### ja · Japonca

- App Name eski (6): Mirivo
- App Name yeni (17): Mirivo: IPTV・メディア
- Subtitle eski (9): IPTVプレーヤー
- Subtitle yeni (14): テレビへ転送、停車中のみ視聴
- Promotional Text eski (85 karakter): IPTVと自分のメディアをひとつに。続きから再生、オフライン視聴、Google CastとAirPlayでテレビへ。対応CarPlayでは駐車中に車の画面でも楽しめます。
- Promotional Text yeni (65 karakter): IPTVソースと個人のメディアをひとつに。スマートフォンで視聴し、対応テレビへ転送。対応する車載画面での動画再生は駐車中のみです。
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (40 karakter; 88 UTF-8 bayt): m3u,xtream,映画,シリーズ,ラジオ,動画再生,プレイリスト,オフライン
- Description eski: 1538 karakter; yeni: 1524 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### ko · Korece

- App Name eski (6): Mirivo
- App Name yeni (17): Mirivo: IPTV와 미디어
- Subtitle eski (9): IPTV 플레이어
- Subtitle yeni (16): TV 전송, 주차 중에만 시청
- Promotional Text eski (100 karakter): IPTV와 내 미디어를 한곳에. 이어 보기, 오프라인 감상, Google Cast와 AirPlay로 TV 전송까지. 호환되는 CarPlay에서는 주차 중 차량 화면으로 감상하세요.
- Promotional Text yeni (79 karakter): IPTV 소스와 개인 미디어를 한곳에서. 휴대폰에서 보고 호환 TV로 전송하세요. 지원 차량 화면의 동영상은 주차 중에만 재생할 수 있습니다.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (40 karakter; 86 UTF-8 bayt): m3u,xtream,스트리밍,재생목록,영화,시리즈,라디오,오프라인,동영상
- Description eski: 1737 karakter; yeni: 1700 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### nl · Felemenkçe

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV & media
- Subtitle eski (11): IPTV-speler
- Subtitle yeni (26): Cast TV, alleen stilstaand
- Promotional Text eski (162 karakter): IPTV en media samen. Kijk verder, kijk offline en cast naar je TV met Google Cast en AirPlay. Gebruik compatibele CarPlay-systemen alleen als je geparkeerd staat.
- Promotional Text yeni (151 karakter): Je IPTV-bronnen en persoonlijke media op één plek. Kijk op je telefoon, stuur naar geschikte tv’s en speel video in de auto alleen af als je stilstaat.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (77 karakter; 77 UTF-8 bayt): m3u,xtream,streaming,afspeellijst,films,series,radio,offline,bibliotheek,cast
- Description eski: 3045 karakter; yeni: 3028 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### pl · Lehçe

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV i media
- Subtitle eski (15): Odtwarzacz IPTV
- Subtitle yeni (30): Rzutuj na TV, tylko na postoju
- Promotional Text eski (150 karakter): IPTV i media razem. Wznawiaj, oglądaj offline i przesyłaj na TV przez Google Cast i AirPlay. Korzystaj ze zgodnego CarPlay tylko w zaparkowanym aucie.
- Promotional Text yeni (146 karakter): Własne źródła IPTV i multimedia w jednym miejscu. Oglądaj na telefonie, przesyłaj na zgodny telewizor, a wideo w aucie odtwarzaj tylko na postoju.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (69 karakter; 69 UTF-8 bayt): m3u,xtream,streaming,playlista,filmy,seriale,radio,offline,biblioteka
- Description eski: 3006 karakter; yeni: 3025 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### pt-BR · Brezilya Portekizcesi

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV e mídia
- Subtitle eski (11): Player IPTV
- Subtitle yeni (28): TV, veja só com carro parado
- Promotional Text eski (148 karakter): IPTV e mídia juntas. Continue de onde parou, veja offline e envie à TV com Google Cast e AirPlay. Use CarPlay compatível só com o carro estacionado.
- Promotional Text yeni (161 karakter): Suas fontes IPTV e mídias pessoais em um só lugar. Assista no celular, envie para TVs compatíveis e reproduza vídeos no carro somente quando estiver estacionado.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (79 karakter; 81 UTF-8 bayt): m3u,xtream,streaming,playlist,filmes,séries,rádio,offline,biblioteca,transmitir
- Description eski: 2969 karakter; yeni: 3026 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### ru · Rusça

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV и медиа
- Subtitle eski (10): IPTV-плеер
- Subtitle yeni (30): На ТВ, видео только на стоянке
- Promotional Text eski (143 karakter): IPTV и медиа вместе. Продолжайте просмотр, смотрите офлайн и на ТВ с Google Cast и AirPlay. Совместимый CarPlay — только в припаркованном авто.
- Promotional Text yeni (152 karakter): Ваши IPTV-источники и личные медиа в одном месте. Смотрите на телефоне, передавайте на совместимые ТВ, а видео в автомобиле включайте только на стоянке.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (43 karakter; 72 UTF-8 bayt): m3u,xtream,стриминг,плейлист,фильмы,сериалы
- Description eski: 3058 karakter; yeni: 3097 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### sv · İsveççe

- App Name eski (6): Mirivo
- App Name yeni (22): Mirivo: IPTV och media
- Subtitle eski (12): IPTV-spelare
- Subtitle yeni (29): TV, titta bara när bilen står
- Promotional Text eski (155 karakter): IPTV och media samlat. Fortsätt titta, se offline och casta till TV med Google Cast och AirPlay. Titta via kompatibla CarPlay-system när bilen är parkerad.
- Promotional Text yeni (151 karakter): Dina IPTV-källor och personliga medier på ett ställe. Titta i mobilen, skicka till en kompatibel TV och spela video i bilen endast när den står stilla.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (73 karakter; 73 UTF-8 bayt): m3u,xtream,streaming,spellista,filmer,serier,radio,offline,bibliotek,cast
- Description eski: 2904 karakter; yeni: 2951 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### th · Tayca

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV และสื่อ
- Subtitle eski (16): เครื่องเล่น IPTV
- Subtitle yeni (25): ส่งขึ้นทีวี ดูเฉพาะตอนจอด
- Promotional Text eski (135 karakter): รวม IPTV และสื่อไว้ด้วยกัน ดูต่อจากจุดเดิม ดูออฟไลน์ ส่งขึ้น TV ด้วย Google Cast และ AirPlay หรือดูผ่าน CarPlay ที่รองรับเมื่อจอดรถแล้ว
- Promotional Text yeni (118 karakter): แหล่ง IPTV และสื่อส่วนตัวของคุณในที่เดียว รับชมบนโทรศัพท์ ส่งไปยังทีวีที่รองรับ และเล่นวิดีโอบนหน้าจอรถเฉพาะเมื่อจอดรถ
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (32 karakter; 70 UTF-8 bayt): m3u,xtream,สตรีม,ภาพยนตร์,ซีรีส์
- Description eski: 2499 karakter; yeni: 2490 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### tr · Türkçe

- App Name eski (6): Mirivo
- App Name yeni (21): Mirivo: IPTV ve Medya
- Subtitle eski (22): IPTV ve Medya Oynatıcı
- Subtitle yeni (30): TV'ye Aktar, Park Halinde İzle
- Promotional Text eski (170 karakter): IPTV ve medyanı tek yerde topla. Kaldığın yerden devam et, çevrimdışı izle; Google Cast ve AirPlay ile TV’ye aktar. Uyumlu CarPlay ile park halindeyken araç ekranında aç.
- Promotional Text yeni (158 karakter): IPTV kaynakların ve kişisel medyan tek yerde. Telefonunda izle, uyumlu TV’lere aktar. Desteklenen araç ekranlarında video yalnızca park halindeyken oynatılır.
- Keywords eski (93 karakter; 99 UTF-8 bayt): m3u,xtream,cast,oynatıcı,video,film,dizi,canlı,yayın,radyo,altyazı,ekran,yansıtma,indir,medya
- Keywords yeni (80 karakter; 88 UTF-8 bayt): m3u,xtream,canlı yayın,film,dizi,radyo,video oynatıcı,oynatma listesi,çevrimdışı
- Description eski: 2867 karakter; yeni: 2876 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### uk · Ukraynaca

- App Name eski (6): Mirivo
- App Name yeni (20): Mirivo: IPTV і медіа
- Subtitle eski (10): IPTV-плеєр
- Subtitle yeni (28): На ТВ, відео лише на стоянці
- Promotional Text eski (139 karakter): IPTV і медіа разом. Продовжуйте перегляд, дивіться офлайн і на ТБ із Google Cast та AirPlay. Сумісний CarPlay — лише в припаркованому авто.
- Promotional Text yeni (150 karakter): Власні IPTV-джерела й особисті медіа в одному місці. Дивіться на телефоні, передавайте на сумісний телевізор, а відео в авто вмикайте лише на стоянці.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (43 karakter; 72 UTF-8 bayt): m3u,xtream,стримінг,плейлист,фільми,серіали
- Description eski: 3015 karakter; yeni: 3025 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### vi · Vietnamca

- App Name eski (6): Mirivo
- App Name yeni (29): Mirivo: IPTV & đa phương tiện
- Subtitle eski (15): Trình phát IPTV
- Subtitle yeni (28): Chiếu lên TV, chỉ xem lúc đỗ
- Promotional Text eski (126 karakter): Gom IPTV và media. Xem tiếp, xem offline, truyền lên TV qua Google Cast và AirPlay. Xem trên CarPlay tương thích khi xe đã đỗ.
- Promotional Text yeni (150 karakter): Nguồn IPTV và nội dung cá nhân của bạn ở cùng một nơi. Xem trên điện thoại, truyền đến TV tương thích và chỉ phát video trên màn hình xe khi xe đã đỗ.
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (69 karakter; 81 UTF-8 bayt): m3u,xtream,phát trực tuyến,danh sách,phim,loạt phim,radio,ngoại tuyến
- Description eski: 2867 karakter; yeni: 2885 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### zh-Hans · Basitleştirilmiş Çince

- App Name eski (6): Mirivo
- App Name yeni (14): Mirivo：IPTV与媒体
- Subtitle eski (7): IPTV播放器
- Subtitle yeni (13): 投屏到电视，仅限停车时观看
- Promotional Text eski (91 karakter): IPTV 和个人媒体，一处尽享。从上次停下的地方继续，下载离线观看，用 Google Cast 和 AirPlay 投放到电视；兼容的 CarPlay 系统可在停车时于车载屏幕播放。
- Promotional Text yeni (50 karakter): IPTV 来源与个人媒体，一处管理。可在手机上观看并投放到兼容电视。车辆屏幕视频仅限车辆停放时播放。
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (42 karakter; 90 UTF-8 bayt): m3u,xtream,直播电视,影视,剧集,电台,视频播放器,播放列表,离线,媒体库
- Description eski: 1235 karakter; yeni: 1177 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

### zh-Hant · Geleneksel Çince

- App Name eski (6): Mirivo
- App Name yeni (14): Mirivo：IPTV與媒體
- Subtitle eski (7): IPTV播放器
- Subtitle yeni (13): 投放至電視，僅限停車時觀看
- Promotional Text eski (92 karakter): IPTV 與個人媒體，一處盡享。從上次停下的地方繼續，下載離線觀看，透過 Google Cast 和 AirPlay 投放到電視；相容的 CarPlay 系統可於停車時在車載螢幕播放。
- Promotional Text yeni (50 karakter): IPTV 來源與個人媒體，一處管理。可在手機上觀看並投放至相容電視。車載螢幕影片僅限車輛停妥時播放。
- Keywords eski (63 karakter; 63 UTF-8 bayt): iptv,m3u,xtream,video,player,stream,airplay,cast,captions,media
- Keywords yeni (42 karakter; 90 UTF-8 bayt): m3u,xtream,直播電視,電影,影集,電台,影片播放器,播放列表,離線,媒體庫
- Description eski: 1250 karakter; yeni: 1191 karakter. Açılış ve büyük ekran bölümü değiştirildi. Diğer özellik bölümleri, abonelik ve içerik/hukuk metinleri aynen korundu. Tam açıklamalar aşağıda Türkçe, İngilizce ve Almanca için; diğer dillerin tam metinleri locale metadata dosyalarında.

## Otomatik sınır ve koruma kontrolü

- Locale dosyası: 22/22.
- Her locale için App Name ≤30, Subtitle ≤30, Promotional Text ≤170, Description ≤4.000 karakter ve Keywords ≤100 UTF-8 bayt sınırı otomatik kontrol edildi. Hepsi geçti.
- Alanlar dolu; keyword tekrarları yok. Beş alanda AirPlay, CarPlay, Google Cast, Miracast veya DLNA adı yok.
- Abonelik denemesi, uygunluk, fiyat ve dönem, otomatik yenileme, iptal için 24 saat, uygulamayı silme, satın alımları geri yükleme ve içerik/DRM açıklamaları kaynak metadata ile birebir aynı kaldı. privacyPolicyURL, termsURL, supportURL, marketingURL ve whatsNew alanları 22 locale’de değişmedi.

### Karakter ve bayt sayım özeti

| Locale | Ad eski→yeni | Subtitle eski→yeni | Tanıtım eski→yeni | Açıklama eski→yeni karakter | Keywords eski→yeni karakter / bayt | Parkta izleme alternatifi (karakter) |
|---|---:|---:|---:|---:|---:|---|
| ar | 6→19 | 9→28 | 147→134 | 2476→2454 | 63 / 63→50 / 83 | للتلفاز، شاهد عند الوقوف فقط (28) |
| de | 6→21 | 11→27 | 143→155 | 3126→3134 | 63 / 63→71 / 71 | TV-Cast; Video nur im Stand (27) |
| en | 6→20 | 11→30 | 146→153 | 2877→2835 | 63 / 63→71 / 71 | Cast to TV, Watch While Parked (30) |
| es | 6→21 | 16→28 | 148→159 | 3167→3209 | 63 / 63→76 / 78 | Envía a TV, mira solo parado (28) |
| fr | 6→23 | 12→27 | 145→162 | 3269→3301 | 63 / 63→72 / 74 | TV Cast; vidéo qu’à l’arrêt (27) |
| he | 6→18 | 8→29 | 137→114 | 2332→2345 | 63 / 63→58 / 97 | לטלוויזיה, צפו רק כשהרכב חונה (29) |
| hi | 6→22 | 11→29 | 154→130 | 2748→2727 | 63 / 63→31 / 67 | TV पर भेजें, पार्क करके देखें (29) |
| id | 6→20 | 12→28 | 151→146 | 2917→2943 | 63 / 63→78 / 78 | TV, tonton hanya saat parkir (28) |
| it | 6→20 | 12→28 | 147→144 | 3063→3093 | 63 / 63→68 / 68 | TV-Cast; video solo in sosta (28) |
| ja | 6→17 | 9→14 | 85→65 | 1538→1524 | 63 / 63→40 / 88 | テレビへ転送、停車中のみ視聴 (14) |
| ko | 6→17 | 9→16 | 100→79 | 1737→1700 | 63 / 63→40 / 86 | TV 전송, 주차 중에만 시청 (16) |
| nl | 6→20 | 11→26 | 162→151 | 3045→3028 | 63 / 63→77 / 77 | Cast TV, alleen stilstaand (26) |
| pl | 6→20 | 15→30 | 150→146 | 3006→3025 | 63 / 63→69 / 69 | Rzutuj na TV, tylko na postoju (30) |
| pt-BR | 6→20 | 11→28 | 148→161 | 2969→3026 | 63 / 63→79 / 81 | TV, veja só com carro parado (28) |
| ru | 6→20 | 10→30 | 143→152 | 3058→3097 | 63 / 63→43 / 72 | На ТВ, видео только на стоянке (30) |
| sv | 6→22 | 12→29 | 155→151 | 2904→2951 | 63 / 63→73 / 73 | TV, titta bara när bilen står (29) |
| th | 6→20 | 16→25 | 135→118 | 2499→2490 | 63 / 63→32 / 70 | ส่งขึ้นทีวี ดูเฉพาะตอนจอด (25) |
| tr | 6→21 | 22→30 | 170→158 | 2867→2876 | 93 / 99→80 / 88 | TV'ye Aktar, Park Halinde İzle (30) |
| uk | 6→20 | 10→28 | 139→150 | 3015→3025 | 63 / 63→43 / 72 | На ТВ, відео лише на стоянці (28) |
| vi | 6→29 | 15→28 | 126→150 | 2867→2885 | 63 / 63→69 / 81 | Chiếu lên TV, chỉ xem lúc đỗ (28) |
| zh-Hans | 6→14 | 7→13 | 91→50 | 1235→1177 | 63 / 63→42 / 90 | 投屏到电视，仅限停车时观看 (13) |
| zh-Hant | 6→14 | 7→13 | 92→50 | 1250→1191 | 63 / 63→42 / 90 | 投放至電視，僅限停車時觀看 (13) |

## Güncellenen alt başlıklar

Türkçe seçenek yerel taslağa uygulandı; diğer 21 dil TV’ye aktarım ve araç park halindeyken izleme anlamını koruyacak şekilde yeniden gözden geçirildi. Sayımlar Unicode code point ile yapıldı.

| Locale | Yeni alt başlık | Karakter |
|---|---|---:|
| ar | للتلفاز، شاهد عند الوقوف فقط | 28 |
| de | TV-Cast; Video nur im Stand | 27 |
| en | Cast to TV, Watch While Parked | 30 |
| es | Envía a TV, mira solo parado | 28 |
| fr | TV Cast; vidéo qu’à l’arrêt | 27 |
| he | לטלוויזיה, צפו רק כשהרכב חונה | 29 |
| hi | TV पर भेजें, पार्क करके देखें | 29 |
| id | TV, tonton hanya saat parkir | 28 |
| it | TV-Cast; video solo in sosta | 28 |
| ja | テレビへ転送、停車中のみ視聴 | 14 |
| ko | TV 전송, 주차 중에만 시청 | 16 |
| nl | Cast TV, alleen stilstaand | 26 |
| pl | Rzutuj na TV, tylko na postoju | 30 |
| pt-BR | TV, veja só com carro parado | 28 |
| ru | На ТВ, видео только на стоянке | 30 |
| sv | TV, titta bara när bilen står | 29 |
| th | ส่งขึ้นทีวี ดูเฉพาะตอนจอด | 25 |
| tr | TV'ye Aktar, Park Halinde İzle | 30 |
| uk | На ТВ, відео лише на стоянці | 28 |
| vi | Chiếu lên TV, chỉ xem lúc đỗ | 28 |
| zh-Hans | 投屏到电视，仅限停车时观看 | 13 |
| zh-Hant | 投放至電視，僅限停車時觀看 | 13 |

## Description değişiklikleri

Her dilde açıklamanın başına yerel “Medyan. Her Ekranda.” karşılığı eklendi. Açılış paragrafı IPTV kaynakları ile kişisel medyayı bir araya getirme, uyumlu TV’ye aktarım ve desteklenen araç ekranlarında yalnızca park halindeyken kullanım şartlarını anlatacak şekilde yenilendi. “Büyük ekrana taşı” bölümü uyumlu TV/alıcı aktarımı ile araç ekranlarında parkta kullanım sınırını açıklayacak şekilde değiştirildi. Diğer özellik bölümleri yedekten aynen taşındı.

Abonelik koşullarının korunduğu otomatik olarak kaynakla karşılaştırıldı: ücretsiz deneme ve uygunluk, satın alma öncesi fiyat/dönem/deneme süresi, otomatik yenileme, denemenin ücretli aboneliğe dönüşmesi, en az 24 saat önce iptal, uygulamayı silmenin iptal sayılmaması, satın alımları geri yükleme ve App Store’dan abonelik yönetimi metinleri aynen duruyor. İçerik sağlanmadığı, hak sahibi olunan içeriğin kullanılması, canlı/DRM içeriğinin indirilememesi, ekran paylaşımının alıcı/kaynak iznine bağlı olması ve DRM/araç güvenlik kısıtlamalarının aşılmaması açıklamaları aynen duruyor. Yerel politika, koşul, destek ve pazarlama URL’leri değişmedi.

## Türkçe Description

    Medyan. Her Ekranda.

    IPTV kaynaklarını ve kişisel medyanı tek yerde topla. iPhone’unda izle, uyumlu TV’lere aktar; desteklenen araç ekranlarında videoyu yalnızca park halindeyken oynat.

    Mirivo, kendi IPTV kaynakların ve kişisel medyan için reklamsız bir oynatıcı ve ekran paylaşımı uygulamasıdır.

    Kendi kitaplığını oluştur
    • M3U oynatma listeni, yayın bağlantını veya Xtream Codes bilgilerini ekle.
    • Film, dizi, canlı yayın ve radyo içeriklerini kaynağındaki kategorilerden bul.
    • Dizilerini sezon ve bölüm sırasıyla takip et; aramayla aradığın içeriğe ulaş.
    • Sevdiklerini favorilerine ekle ve izlemeye kaldığın yerden devam et.

    İndir, internet olmadan izle
    Sağlayıcının izin verdiği uygun film ve bölümleri iPhone’una indir. İndirdiklerini tek yerden aç, yönet ve çevrimdışı izle.

    Büyük ekrana taşı
    Fotoğraf ve videolarını uyumlu TV ve alıcılara aktar. Desteklenen araç ekranlarında video yalnızca park halindeyken kullanılabilir. Özellikler cihaz, araç ve içerik uyumluluğuna bağlıdır.

    Fotoğrafların ve dosyaların da yanında
    Fotoğraflarını slayt gösterisine dönüştür, arşivindeki videoları aç, iPhone veya iCloud Drive’dan müzik ve dosya seç. Bir bağlantıyı kitaplığına kaydetmeden oynatabilir, iPhone ekranını ve uygun uygulama sesini paylaşabilirsin.

    İzleme deneyimini kendine göre ayarla
    Tam ekran ve görüntü boyutu seçeneklerini kullan. Kaynağın sunduğu ses dili ve altyazılar arasından seçim yap. Cihaz içi canlı altyazılar iOS 26 ile desteklenen cihaz ve dillerde kullanılabilir.

    Mirivo Pro
    Kaynak ekleme ve kitaplıkta gezinme üyelik öncesinde kullanılabilir. Oynatma, indirme ve ekran paylaşımı için etkin ücretsiz deneme veya Mirivo Pro gerekir. Haftalık ve yıllık abonelikler aynı Pro özelliklerini açar.

    Ücretsiz deneme, varsa yalnızca uygun hesaplara sunulur. Güncel fiyat, dönem, deneme süresi ve deneme sonrası ücret satın alma öncesinde gösterilir. Abonelikler otomatik yenilenir; deneme iptal edilmezse ücretli aboneliğe dönüşür. Ödeme Apple hesabından alınır. Yenilenmesini istemiyorsan deneme veya dönem bitiminden en az 24 saat önce App Store’dan iptal et. Uygulamayı silmek aboneliği iptal etmez. Satın alımlarını geri yükleyebilir ve aboneliğini App Store’dan yönetebilirsin.

    İçerik ve uyumluluk
    Mirivo kanal, film, dizi, IPTV hesabı veya içerik aboneliği sağlamaz. İçeriklerini kendi kaynaklarından eklersin. Yalnızca erişme ve indirme hakkın olan içerikleri kullan. Canlı yayınlar ve DRM korumalı içerikler indirilemez. Ekran paylaşımı, kaynak uygulamanın ve alıcı cihazın izin verdiği içeriklerle çalışır; Mirivo DRM veya araç güvenlik kısıtlamalarını kaldırmaz.

    Gizlilik: https://mirivo-support.netlify.app/tr/privacy.html
    Kullanım koşulları: https://mirivo-support.netlify.app/tr/terms.html
    Destek: https://mirivo-support.netlify.app/tr/support.html
    Apple Standart EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## English Description

    Your Media. Every Screen.

    Bring your IPTV sources and personal media together. Watch on iPhone, send to compatible TVs, or play video on supported vehicle screens while parked.

    Mirivo is an ad-free player and screen-sharing app for your own IPTV sources and personal media.

    Build your own library
    • Add an M3U playlist, stream link or Xtream Codes credentials.
    • Find movies, series, live streams and radio in your source’s categories.
    • Follow series by season and episode, and find what you want with search.
    • Save favorites and pick up where you left off.

    Download and watch offline
    Download eligible movies and episodes to your iPhone when your provider permits it. Open, manage and watch your downloads offline in one place.

    Take it to the big screen
    Send photos and videos to compatible TVs and receivers. Video on supported vehicle screens is for use while parked. Features depend on device, vehicle and content compatibility.

    Your photos and files, too
    Turn photos into a slideshow, play videos from your collection, and choose music or files from your iPhone or iCloud Drive. Play a link without saving it to your library, or share your iPhone screen and supported app audio.

    Make watching your own
    Use full-screen and picture-size options. Choose the audio languages and subtitles provided by your source. On-device live captions are available with iOS 26 on supported devices and in supported languages.

    Mirivo Pro
    Add sources and browse your library before subscribing. Playback, downloads and screen sharing require an active free trial or Mirivo Pro. Weekly and yearly subscriptions unlock the same Pro features.

    Free trials, when available, are offered only to eligible accounts. The current price, billing period, trial duration and post-trial charge are shown before purchase. Subscriptions renew automatically; a trial becomes a paid subscription unless cancelled. Payment is charged to your Apple account. To prevent renewal, cancel in the App Store at least 24 hours before the trial or current period ends. Deleting the app does not cancel a subscription. Restore purchases and manage your subscription in the App Store.

    Content and compatibility
    Mirivo does not provide channels, movies, series, IPTV accounts or content subscriptions. You add content from your own sources. Use only content you have the right to access and download. Live streams and DRM-protected content cannot be downloaded. Screen sharing works with content permitted by the source app and receiving device. Mirivo does not remove DRM or vehicle safety restrictions.

    Privacy: https://mirivo-support.netlify.app/en/privacy.html
    Terms: https://mirivo-support.netlify.app/en/terms.html
    Support: https://mirivo-support.netlify.app/en/support.html
    Apple Standard EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## Deutsche Description

    Deine Medien. Auf jedem Bildschirm.

    Führe deine IPTV-Quellen und persönlichen Medien an einem Ort zusammen. Sieh sie auf dem iPhone, übertrage sie auf kompatible Fernseher oder spiele Videos auf unterstützten Fahrzeugdisplays nur im Stand ab.

    Mirivo ist ein werbefreier Player mit Bildschirmfreigabe für deine eigenen IPTV-Quellen und persönlichen Medien.

    Deine eigene Mediathek
    • Füge M3U-Wiedergabelisten, Stream-Links oder Zugangsdaten für Xtream Codes hinzu.
    • Entdecke Filme, Serien, Livestreams und Radio in den Kategorien deiner Quelle.
    • Folge Serien nach Staffel und Folge und finde Inhalte über die Suche.
    • Speichere Favoriten und schaue dort weiter, wo du aufgehört hast.

    Herunterladen und offline schauen
    Lade geeignete Filme und Folgen auf dein iPhone, sofern dein Anbieter dies erlaubt. Öffne und verwalte Downloads an einem Ort und schau sie ohne Internet an.

    Auf den großen Bildschirm
    Übertrage Fotos und Videos auf kompatible Fernseher und Empfänger. Videos auf unterstützten Fahrzeugdisplays sind nur im Stand verfügbar. Die Funktionen hängen von Gerät, Fahrzeug und Inhalt ab.

    Auch deine Fotos und Dateien
    Erstelle Diashows aus Fotos, spiele Videos aus deiner Sammlung ab und wähle Musik oder Dateien vom iPhone oder aus iCloud Drive. Öffne Links, ohne sie in der Mediathek zu speichern, oder teile deinen iPhone-Bildschirm und unterstützten App-Ton.

    Dein Seherlebnis
    Nutze Vollbild und Optionen für die Bildgröße. Wähle aus den Tonsprachen und Untertiteln deiner Quelle. Live-Untertitel auf dem Gerät sind mit iOS 26 auf unterstützten Geräten und in unterstützten Sprachen verfügbar.

    Mirivo Pro
    Quellen hinzufügen und die Mediathek durchsuchen kannst du vor dem Abonnieren. Wiedergabe, Downloads und Bildschirmfreigabe erfordern eine aktive kostenlose Testphase oder Mirivo Pro. Wochen- und Jahresabos bieten dieselben Pro-Funktionen.

    Kostenlose Testphasen sind, falls verfügbar, nur für berechtigte Konten vorgesehen. Aktueller Preis, Abrechnungszeitraum, Testdauer und Preis danach werden vor dem Kauf angezeigt. Abos verlängern sich automatisch; ohne Kündigung wird die Testphase kostenpflichtig. Die Zahlung erfolgt über dein Apple-Konto. Kündige im App Store mindestens 24 Stunden vor Ende der Testphase oder des laufenden Zeitraums, um die Verlängerung zu verhindern. Das Löschen der App kündigt kein Abo. Käufe lassen sich wiederherstellen und Abos im App Store verwalten.

    Inhalte und Kompatibilität
    Mirivo stellt keine Sender, Filme, Serien, IPTV-Konten oder Inhaltsabos bereit. Inhalte fügst du aus eigenen Quellen hinzu. Nutze nur Inhalte, auf die du zugreifen und die du herunterladen darfst. Livestreams und DRM-geschützte Inhalte sind nicht herunterladbar. Bildschirmfreigabe funktioniert nur, wenn Quell-App und Empfangsgerät dies erlauben. Mirivo hebt weder DRM- noch Fahrzeugsicherheitsbeschränkungen auf.

    Datenschutz: https://mirivo-support.netlify.app/en/privacy.html
    Nutzungsbedingungen: https://mirivo-support.netlify.app/en/terms.html
    Support: https://mirivo-support.netlify.app/en/support.html
    Apple-Standard-EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## Yayınlanmış sürüm ve araç ekranında video kanıtı

- ASC dağıtım sayfası iOS 1.0 için **Ready for Distribution** gösteriyor; görünen sayfada onaylı build numarası yok. TestFlight’ta son listelenen **build 49 Testing** durumunda. Yerel `build/deploy/app-review-49-upload.json`, 1.0 (49) gönderiminin **Waiting for Review** kaydını tutuyor. Bunlar yayınlanmış binary’nin build numarasını belirlemiyor.
- Build 49’un arşivi ve imzalı binary’si çalışma alanında bulunmadığından entitlement’ını doğrudan doğrulamak mümkün olmadı. `build/deploy/carplay-audio-review-verification.json` yalnızca **Debug build 48** için imzada Audio olduğunu doğruluyor; yayın kanıtı değil.
- `docs/DEPLOYMENT.md` 3 Kasım düzeltmesinde Video entitlement’ının kaldırıldığını belirtiyor. Ancak mevcut `Config/App.entitlements` hem `com.apple.developer.carplay-audio` hem `com.apple.developer.carplay-video` anahtarlarını içeriyor. Bu dosya bu görevde değiştirilmedi. Kaynak durumuyla doküman arasındaki fark giderilmeden entitlement düzeltmesi doğrulanmış sayılamaz.
- Build 40 ve önceki yerel iPhone + CarPlay Simulator denemeleri yalnız debug/yerel davranışı gösteriyor. Gerçek araç ve App Store binary’si için video kabulü kanıtı yok.

## App Review entitlement ret kaydı

`docs/DEPLOYMENT.md`, Apple’ın 1.0 (41) için 2.5.1 kapsamında CarPlay Video entitlement’ının kaldırılmasını istediğini kaydediyor. Sonraki onay kaydı ve build’e bağlı imzalı entitlement kanıtı bulunamadı. Mevcut entitlement dosyası da Audio+Video içerdiğinden ret gerekçesinin onaylı sürümde giderildiği doğrulanamıyor. Bu kontrolde entitlement ayarı değiştirilmedi.
## Marka notu

Türkçe alt başlık yerel taslakta “TV'ye Aktar, Park Halinde İzle” oldu. Diğer 21 dilin son değerleri ve sayıları yukarıdaki tabloda. Arama hacmi verisi yok; keywords listeleri hacim iddiası değildir.

## App Store Connect durumu

Locale listesi canlı ASC seçicisinden doğrulandı; depo kodlarıyla 22/22 eşleşiyor. Alanlar salt okunur, Save pasif. Türkçe canlı alanlar görüntülendi; diğer dillerin içerik değerleri topluca okunamadı. Taslağın ASC’ye girilmesi ve her locale için canlı değer karşılaştırması, onaydan sonra elle yapılmalı. Bu tur hiçbir alan kaydedilmedi.

## Son durum

- 22 locale için son `subtitle` değerleri belirlendi; bu turda 19 dosyanın alanı değişti, İngilizce/Rusça/Ukraynaca değerleri zaten aynıydı. Name, promotionalText, keywords, description, abonelik ve hukuki metinler, URL’ler ve whatsNew alanları önceki kopyayla bire bir aynı.
- Bütün yeni alt başlıklar 30 karakter sınırında veya altında; alan sınırları ve keyword UTF-8 bayt sınırları yeniden doğrulandı.
- App Store Connect’te kayıt/yükleme yapılmadı; yeni sürüm oluşturulmadı ve App Review’a gönderim yapılmadı. Aşama 2’de bekliyor.
- Açık riskler: ASC alan değerlerinin diğer 21 locale’de canlı karşılaştırması; yayınlanan build numarası ve onaylı binary’de CarPlay video/entitlement kanıtı; mevcut entitlement dosyası ile deployment belgesi arasındaki uyumsuzluk.
