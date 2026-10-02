MIRIVO — Netlify ve App Store teslim dosyaları

Netlify:
1. mirivo-netlify.zip dosyasını aç. index.html ZIP'in kökündedir.
2. Çıkardığın klasörü Netlify manuel deploy alanına bırak.
3. Oluşan alan adında /privacy.html, /terms.html, /support.html adreslerini kontrol et.
4. App Store Connect gizlilik URL'sine /privacy.html, destek URL'sine /support.html gir.
   İngilizce doğrudan adresler: /en/privacy.html, /en/terms.html, /en/support.html.

Sitede yapılandırılacak anahtar, API, reklam, analitik, form veya çerez yoktur.
Destek: alperrbicer@gmail.com. Yayıncı: Alper Biçer.
Uygulama aynı belgeleri çevrimdışı içerir; Netlify alan adı henüz belli olmadığı için
uydurma bir alan adı uygulamaya yazılmadı.

AppStore/tr ve AppStore/en: alan uzunlukları kontrol edilmiş metadata JSON dosyaları.
AppStore/review-notes.txt: inceleme hazırlığı, gerçek araç kanıtı eklenmeden gönderilmez.
AppStore/privacy-inventory.json: mevcut veri akışının envanteri.

Pro satışları kullanıcı kararıyla kapalıdır; ilk sürümde özellikler açık ve reklamsızdır.
Tests/App/Mirivo.storekit içindeki fiyatlar yalnızca yerel test verisidir; satış fiyatı değildir.
Haftalık, yıllık ve ömür boyu ürünler daha sonra App Store Connect'te oluşturulup
fiyatlandırılacak; gerçek fiyatlar StoreKit'ten alınacak.

Bu paket imzalı iOS uygulaması, TestFlight yüklemesi veya Apple onayı içermez.
Güncel doğrulama ve dış bağımlılıklar: ../docs/IMPLEMENTATION_STATUS.md.
