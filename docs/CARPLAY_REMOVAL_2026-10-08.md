# CarPlay’siz App Store adayı — 8 Ekim 2026

CarPlay entegrasyonunun kaldırılması `87329eb` olarak kaydedildi. Başlangıçtaki PiP düzeltmesi `9a4730d`, destek sitesi düzenlemesi `ca21df1` olarak ayrı kaydedildi.

## Değişiklikler

- CarPlay sahnesi, framework importu, Audio/Video entitlement dosyaları, alternatif scheme/yapılandırmalar kaldırıldı.
- Kaynak oynatma CarPlay bağlantısından bağımsız; TV/harici ekran yayın durumu ayrı korunuyor.
- CarPlay bağlantı hatırlatması ve ayarı kaldırıldı. Önceki sürümden kalan zamanlanmış bildirim ve tercihleri açılışta temizleniyor.
- Oynatıcıdaki bağımsız büyük kontrol düzeni “Araç modu” yerine “Büyük kontroller” adını ve el simgesini kullanır; herhangi bir araç bağlantısı vaat etmez.
- 22 dilde CarPlay metinleri kaldırıldı. Bağlantı rehberi Google Cast/AirPlay; ortak slogan büyük ekranı anlatıyor.
- Dağıtım araçları App Group, APNs, App Attest ve gerçek imza/profil denetimlerini koruyor; eski CarPlay arşivini veya imzalı CarPlay yetkisini reddediyor.
- 22 yerelleştirmede açıklama, tanıtım ve anahtar sözcükler; Review/TestFlight notları güncellendi. Alt başlıklarda CarPlay yerine AirPlay.
- Altıncı ekran görüntüsü CarPlay yerine AirPlay rehberini gösteriyor. Görseller gerçek uygulamadan sentetik demo medyasıyla yeniden alınıyor; görsel düzenleme yapılmıyor.

## Doğrulama ve canlı durum

- 25 dağıtım betiği ve 48 Swift çekirdek/medya testi geçti; uygulama/test hedefleri tam derlendi.
- Son 51 oynatıcı testi geçti; 3 isteğe bağlı sağlayıcı testi atlandı. Hedefli geometri, büyük kontroller ve Pro plan testleri geçti.
- 22 dil için 132 gerçek iPhone ekran görüntüsü üretildi ve App Store Connect'e yüklendi. Her dilin altı görsel sırası ve küçük ekranlara devralınması tekrar açılarak doğrulandı; SHA256/boyut/test kökeni kontrol edildi. İlk toplu UI koşularında geçiş zamanlaması hataları vardı; yalnız başarılı testlerin görselleri kullanıldı ve eksik Basitleştirilmiş Çince oynatıcı çekimi hedefli tekrar geçti.
- CarPlay’siz 1.0 (13) arşivi ve IPA üretildi; uygulama ve yayın uzantısının imza/profilleri, App Group/APNs/App Attest, CarPlay entitlement ve sahne yokluğu doğrulandı. Apple yüklemesi tamamlandı; işlenen build 13 sürüm 1.0'a seçildi ve tekrar açılarak doğrulandı. Manuel yayın korunuyor.
- Yükleme başarılı; FirebaseAnalytics/GoogleAppMeasurement/GoogleCast satıcı dSYM uyarıları mevcut. Arşiv/IPA ve yükleme kayıtları `build/deploy/standalone-13` altında korunuyor.
- Canlı 22 dil mağaza metni doğrulandı. Yıllık ve Ömür Boyu Pro inceleme notları ve gerçek ödeme ekranı görselleri yenilendi; iki ürün ve 22 yerelleştirmeli abonelik grubu aynı inceleme taslağında. Haftalık eski ürün eklenmedi.
- Netlify production `6ac76de66c37abc79edcdf26` Published. Sekiz Türkçe/İngilizce canlı sayfa HTTP, tarih, CarPlay ve eski Araç modu adının yokluğu bakımından doğrulandı.
- Statik yayın kontrolü: 12 HTML, 22 dil, 272 anahtar, 5984 çeviri değeri; sıfır hata.
- **Son gönderim yapılmadı.** Apple'ın Add for Review kontrolü üç eksik bildiriyor: App Privacy yayımlama beyanı, yaş derecelendirmesi yanıtları, Content Rights. Uygulama sürümü bu üç beyan tamamlanmadan taslağa eklenemiyor. Ayrıntılar: `Release/AppStore/owner-decisions-20261008.md`; canlı kanıt `portal-proof-20261008-review-blockers.jpg`.

Yerel/simülatör testleri fiziksel Google Cast/AirPlay, gerçek sandbox satın alma/geri yükleme veya Apple kabulü kanıtı değildir. Önceki tarihli belgeler tarihsel kayıt olarak korunur. DSA/tacir statüsü ve gerekiyorsa sözleşme/banka/vergi işlemleri hesap sahibine bırakıldı.
