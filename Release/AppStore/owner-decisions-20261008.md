# Mirivo 1.0 (13): hesap sahibi kararları

Teknik hazırlık bu kararların yerine geçmez. CarPlay bu adayda yoktur; CarPlay Video onayı bu sürümün ön koşulu değildir.

## App Store Connect'te görülen eksikler

- **Content Rights:** App Information hâlâ “Set Up Content Rights Information” gösteriyor. Uygulama geliştirici tarafından kanal/hesap/katalog sunmaz; kullanıcı kendi izinli kaynaklarını ekler. Üçüncü taraf içeriğe erişen bir oynatıcı olduğu için “üçüncü taraf içerik yok” şeklinde otomatik beyan verilmemelidir. Hakların ve hedef ülkelerde kullanımın hukuki değerlendirmesini hesap sahibi onaylamalıdır.
- **Age Ratings:** kurulum yapılmamış. Kodda reklam, sosyal akış, sohbet, kumar veya uygulama içi serbest web tarayıcısı yoktur. Kullanıcının kendi medya/URL kaynaklarını oynatması, içeriğin yaşa uygunluğunu tek başına kanıtlamaz. Apple'ın güncel formuna verilecek yanıtlar ve gerekirse daha yüksek yaş sınırı hesap sahibi tarafından doğrulanmalıdır.
- **App Privacy:** yedi veri türü için kaydedilmiş teknik taslak mevcut; Publish henüz yapılmadı. Satın alma geçmişi, cihaz kimliği, yaklaşık konum ve ürün etkileşimi için muhafazakâr biçimde kimliğe bağlı; performans/diğer tanılama ve diğer veriler için bağlı değil. Takip beyanı yok. Build 13'ün 26 gizlilik manifestinde takip/veri türü bildirimleri build 12 ile aynı; gerçek entegrasyon ve hizmet ayarları ayrıca önemlidir. Taslak: `privacy-form-draft-20261005.json`; yeni arşiv kanıtı: `privacy-manifests-build-13.json`.
- **DSA:** App Information, uygulama için non-trader ve tamamlanması gereken uyumluluk bağlantısını gösteriyor. Pro satışları için trader/non-trader değerlendirmesi hesap sahibinin kararıdır; otomatik değiştirilmedi.
- **Bağlayıcı sözleşmeler, banka/vergi bilgileri:** mevcut duruma ilişkin yeni beyan veya kabul yapılmadı. Gerekiyorsa hesap sahibi tamamlamalıdır.

## Son gönderim

Build 13 sürüme seçildi; 22 dilde 132 görsel doğrulandı. Yıllık/Ömür Boyu ürünler ve abonelik grubu aynı taslağa eklendi. Apple, uygulama sürümünün taslağa eklenmesini yalnız App Privacy, yaş derecelendirmesi ve Content Rights eksikleriyle engelliyor. Bu üç beyan tamamlanınca sürüm aynı taslağa eklenmeli. Hesap sahibi kararları tamamlanmadan son Submit for Review yapılmamalıdır. Manuel yayın seçeneği korunur.

Fiziksel Cast/AirPlay, gerçek Apple sandbox satın alma/geri yükleme ve üretim RevenueCat bildirim teslimi bu hazırlıkla kanıtlanmış sayılmaz.

## Apple kaynakları

- [Yaş derecelendirmesi tanımları](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Uygulama bilgileri ve içerik hakları](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [App Privacy](https://developer.apple.com/app-store/app-privacy-details/)
