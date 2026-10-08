# CarPlay’siz App Store adayı — 8 Ekim 2026

Başlangıçtaki PiP düzeltmesi `9a4730d`, destek sitesi düzenlemesi `ca21df1` olarak ayrı kaydedildi.

## Değişiklikler

- CarPlay sahnesi, framework importu, Audio/Video entitlement dosyaları, alternatif scheme/yapılandırmalar kaldırıldı.
- Kaynak oynatma CarPlay bağlantısından bağımsız; TV/harici ekran yayın durumu ayrı korunuyor.
- CarPlay bağlantı hatırlatması ve ayarı kaldırıldı. Önceki sürümden kalan zamanlanmış bildirim ve tercihleri açılışta temizleniyor.
- 22 dilde CarPlay metinleri kaldırıldı. Bağlantı rehberi Google Cast/AirPlay; ortak slogan büyük ekranı anlatıyor.
- Dağıtım araçları App Group, APNs, App Attest ve gerçek imza/profil denetimlerini koruyor; eski CarPlay arşivini veya imzalı CarPlay yetkisini reddediyor.
- 22 yerelleştirmede açıklama, tanıtım ve anahtar sözcükler; Review/TestFlight notları güncellendi. Alt başlıklarda CarPlay yerine AirPlay.
- Altıncı ekran görüntüsü CarPlay yerine AirPlay rehberini gösteriyor. Görseller gerçek uygulamadan sentetik demo medyasıyla yeniden alınıyor; görsel düzenleme yapılmıyor.

## Doğrulama ve canlı durum

- 25 dağıtım betiği testi geçti.
- 48 Swift çekirdek/medya testi geçti.
- iOS uygulama ve test hedefleri tam derlendi (`TEST BUILD SUCCEEDED`).
- İlk 51 oynatıcı testinde 3 isteğe bağlı sağlayıcı testi atlandı; yalnız tam ekran geometrisi testindeki eski VLC drawable = viewport varsayımı başarısızdı. Artık dış hostun viewport’u doldurması ve iç görüntünün en-boy oranını koruması ayrı doğrulanıyor; tekrar kontrol çalışıyor.
- Netlify production deploy `6ac73c81094257ab2cd32242` Published; canlı İngilizce yardımda Google Cast/AirPlay akışı doğrulandı.
- App Store Connect sürüm 1.0 hâlâ Prepare for Submission; build 12 eski CarPlay Audio adayıdır. Yeni CarPlay’siz build seçilmeden Review’a gönderilmemelidir.
- Yeni ekran görüntüleri, canlı 22 dil metni/alt başlık güncellemeleri, yeni arşiv/IPA/yükleme ve son Review kontrolleri devam ediyor.

Yerel testler fiziksel Google Cast/AirPlay/PiP/sandbox satın alma veya Apple kabulü kanıtı değildir. Önceki tarihli belgeler tarihsel kayıt olarak korunur.
