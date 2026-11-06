# Mirivo Aşama 2 — son kontrol raporu

6 Kasım 2026 · Yerel metadata taslağı; ASC’ye hiçbir şey kaydedilmedi.

## Değişen alan

22 locale için son `subtitle` değerleri belirlendi; bu turda 19 dosya değişti, İngilizce, Rusça ve Ukraynaca değerleri zaten seçilen metinle aynıydı. Her biri 30 karakter veya daha kısa. Name, promotional text, keywords, description, hukuki ve abonelik koşulları, URL’ler ve `whatsNew` değiştirilmedi; önceki metadata yedeğiyle alan alan karşılaştırıldı.

| Locale | Dil | Yeni alt başlık | Karakter |
|---|---|---|---:|
| ar | Arapça | للتلفاز، شاهد عند الوقوف فقط | 28 |
| de | Almanca | TV-Cast; Video nur im Stand | 27 |
| en | İngilizce | Cast to TV, Watch While Parked | 30 |
| es | İspanyolca | Envía a TV, mira solo parado | 28 |
| fr | Fransızca | TV Cast; vidéo qu’à l’arrêt | 27 |
| he | İbranice | לטלוויזיה, צפו רק כשהרכב חונה | 29 |
| hi | Hintçe | TV पर भेजें, पार्क करके देखें | 29 |
| id | Endonezce | TV, tonton hanya saat parkir | 28 |
| it | İtalyanca | TV-Cast; video solo in sosta | 28 |
| ja | Japonca | テレビへ転送、停車中のみ視聴 | 14 |
| ko | Korece | TV 전송, 주차 중에만 시청 | 16 |
| nl | Felemenkçe | Cast TV, alleen stilstaand | 26 |
| pl | Lehçe | Rzutuj na TV, tylko na postoju | 30 |
| pt-BR | Brezilya Portekizcesi | TV, veja só com carro parado | 28 |
| ru | Rusça | На ТВ, видео только на стоянке | 30 |
| sv | İsveççe | TV, titta bara när bilen står | 29 |
| th | Tayca | ส่งขึ้นทีวี ดูเฉพาะตอนจอด | 25 |
| tr | Türkçe | TV'ye Aktar, Park Halinde İzle | 30 |
| uk | Ukraynaca | На ТВ, відео лише на стоянці | 28 |
| vi | Vietnamca | Chiếu lên TV, chỉ xem lúc đỗ | 28 |
| zh-Hans | Basitleştirilmiş Çince | 投屏到电视，仅限停车时观看 | 13 |
| zh-Hant | Geleneksel Çince | 投放至電視，僅限停車時觀看 | 13 |

## Açık kalan riskler

- ASC’de 22 locale listesi depo klasörleriyle eşleşiyor. Türkçe canlı değerler görüldü; diğer 21 locale’in canlı alanları okunamadı. Form salt okunur, Save pasif. Yetkili kullanıcı onaydan sonra değerleri ASC’ye elle girmeli ve her locale’i karşılaştırmalı.
- ASC dağıtım sayfası iOS 1.0 **Ready for Distribution** gösteriyor; yayınlanan build numarası görünmüyor. TestFlight build 49 **Testing**; yerel kayıt bu build için **Waiting for Review** diyor. Onaylı binary build’i doğrulanamadı.
- Araç ekranında video desteğinin onaylı sürümde bulunduğuna dair build’e bağlı kanıt yok. 2.5.1 ret notu Video entitlement’ının kaldırılmasını istiyor; mevcut `Config/App.entitlements` Audio ve Video anahtarlarını birlikte içeriyor, `docs/DEPLOYMENT.md` ise yalnız Audio kaldığını söylüyor. Uyumsuzluk bu görevde değiştirilmedi.

Metadata sınırları yeniden kontrol edildi: Name ≤30, Subtitle ≤30, Promotional Text ≤170, Description ≤4.000 karakter; Keywords ≤100 UTF-8 bayt. Abonelik/hukuk metinleri ve URL’ler yedekle bire bir aynı. Yedek: `Release/AppStore/backups/20261106-before-final-subtitle-review.zip`.

ASC’de değişiklik kaydedilmedi, yeni sürüm açılmadı ve App Review’a gönderim yapılmadı. Aşama 2’de bekliyor.
