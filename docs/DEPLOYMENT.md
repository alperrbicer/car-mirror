# Mirivo iPhone derleme ve dağıtım

8 Ekim 2026: CarPlay Audio/Video uygulamadan kaldırıldı. Tek scheme `CarMirror`, yapılandırmalar `Debug` ve `Release`. Eski CarPlay arşivleri yeniden yüklenemez; yeni arşiv oluşturulmalıdır. `--carplay-video` artık geçersizdir.

macOS, Xcode 27, Node.js 22.12+ ve proje üretimi için Ruby xcodeproj gerekir. Yerel takım ayarı `Config/Local.xcconfig` içindeki `DEVELOPMENT_TEAM` ile belirlenir. Var olan dosyayı koru. Gizli anahtarları Git'e ekleme.

Kimlikler: `com.alperbicer.carmirror`, `com.alperbicer.carmirror.broadcast`, `group.com.alperbicer.carmirror`.

Ana uygulama `Config/App.entitlements` ile App Group, APNs ve üretim App Attest kullanır. Uzantı `Config/Broadcast.entitlements` ile yalnız App Group kullanır. İmza doğrulaması yetkileri, profili, kimlikleri, takım ve süreyi denetler. Dağıtımda production APNs ve App Store profili zorunludur. Profil daha geniş yetkilere sahip olabilir; uygulama imzasında CarPlay bulunamaz.

```sh
ruby scripts/generate_project.rb --replace
node --test Tests/Scripts/deployment.test.mjs
swift test --jobs 2
bun run mobile:doctor
bun run mobile:devices
bun run check --keep-cache
bun run mobile:ios:simulator --device SIMULATOR_UDID --keep-cache
bun run mobile:ios:install --device IPHONE_UDID --allow-provisioning-updates
bun run mobile:ios:archive --allow-provisioning-updates --keep-cache
bun run mobile:ios:export --archive ARCHIVE_PATH --allow-provisioning-updates
bun run mobile:ios:upload --archive ARCHIVE_PATH --allow-provisioning-updates
```

`--preview` yalnız eski kurulum komutlarıyla uyumlu bir takma addır; standart kurulum da CarPlay içermez. Dağıtımda kullanılmaz. `--keep-cache` kullanılmazsa geçici derleme/bağımlılık önbelleği temizlenir; arşivler, IPA, sonuç kayıtları ve build sayacı korunur. Native komutlar tek kilidi paylaşır. Çalışan komut varken projeyi yeniden üretme veya kilidi silme.

Arşivleme testleri çalıştırır ve build numarasını `build/deploy/last-build.json` üzerinden artırır. `--build` kullanmadan önce App Store Connect'teki en son build'i kontrol et. Var olan `--archive` ile build/sürüm değiştirilemez.

CLI yüklemesi için `.env.deploy` içinde APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID ve APP_STORE_CONNECT_PRIVATE_KEY_PATH gerekir. Anahtar yoksa Xcode Organizer'dan mevcut Apple hesabıyla yükleme yapılabilir. Apple'a yükleme App Review'a gönderim veya yayınlama değildir.

Ekran görüntüleri sentetik demo verisiyle gerçek iPhone arayüzünden alınır. Test sunucusu `python3 scripts/capture_store_screenshots.py`; yalnız 127.0.0.1:8769 dinler. 22 dilde aynı altı ekranın sırası: kaynaklar, kanallar, oynatıcı, paylaşım, Xtream, AirPlay rehberi. Demo uygulamaya paketlenmez.

Netlify paketi `python3 scripts/build_site.py` ile hazırlanır; `python3 scripts/verify_release.py` kaynak/metin/ZIP tutarlılığını denetler. Canlı yayın ayrıca doğrulanır.
