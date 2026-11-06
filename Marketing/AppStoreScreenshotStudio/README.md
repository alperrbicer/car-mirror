# Mirivo Screenshot Studio V2

Studio tasarımı yüklediğin `mirivo-screenshot-studio-v2.zip` paketinden alınmıştır. Altı sabit HTML/CSS master, ZIP’teki CSS cihaz sahneleri, 22 uygulama dilindeki mağaza görseli metinleri ve iPhone/iPad önizlemesi korunmuştur. Önceki prototipin tasarım ve Sharp fallback render’ı etkin modülden çıkarıldı; eski dosyalar yalnızca `work/legacy-first-prototype/` altında arşivlendi.

## Yerel önizleme

```sh
bun install
npm run dev -- --port 43001
```

`http://localhost:43001/` adresinde altı master’ı ve dil/cihaz seçimlerini görüntüle. Master’ların kompozisyonu ve arka planı diller arasında değişmez.

`npm run build` bağımsız önizleme sayfalarını, CSS/JS dosyalarını ve gerçek asset’leri `dist/` içine kopyalar. PNG dışa aktarma endpoint’i geliştirme panelinde çalışır.

## PNG üretimi

Python 3, Pillow ve Playwright Chromium gerekir:

```sh
python3 -m pip install -r tools/requirements.txt
python3 -m playwright install chromium
npm run screenshots
npm run screenshots -- --locale tr-TR
npm run screenshots -- --all
```

Varsayılan komut Screenshot 01’i üç örnek dilde ve iki cihaz boyutunda üretir. `--locale` tek dil seçer. `--all` ZIP’teki altı master’ı, üç örnek dili ve iPhone/iPad cihazlarını üretir. Daha dar render için örneğin `npm run screenshots -- --slide 1 --locale de-DE --device ipad` kullan.

PNG’ler `outputs/app-store-screenshots/{locale}/{device}/{01..06}.png` altında oluşur. Üretici boyutları denetler, sRGB ICC profilini ekler, her sayfayı iki kez yakalayıp byte hash’lerini karşılaştırır; font ve yatay metin taşmasını kontrol eder. Eksik screenshot slot’ları sessizce gizlenmez: placeholder görünür ve `render-report.json` içinde listelenir. Contact sheet’ler ve kalite raporu aynı çıktı klasörüne yazılır.

Stüdyo panelindeki **Tüm ekranlar · tüm diller ve cihazlar (ZIP)** düğmesi, desteklenen tüm dillerin altı masterını iPhone ve iPad boyutlarında üretip PNG’leri, contact sheet’leri ve render raporunu tek ZIP olarak indirir.

## Gerçek asset’ler

- Resmî `MirivoMark.svg`, `assets/MirivoMark.svg` içine eklendi.
- `assets/screens/` içinde altı masterın kullandığı telefon, tablet, TV ve araç ekran görselleri bulunur.
- Görsel kaynakları ve işleme notları [asset-provenance.json](asset-provenance.json) içinde kayıtlıdır. Son render raporu `outputs/app-store-screenshots/render-report.json` dosyasındadır.

ZIP README’sindeki gibi bazı pazarlama metinleri özellik iddiası içeriyor. Bu prototip metinleri Mirivo uygulama build’ine ve App Store uygunluğuna göre ayrıca onaylanmalı.

## Kaynaklar

- `index.html`, `styles.css`, `render.js`, `screenshot-01.html` … `screenshot-06.html`, `translations.js`
- `tools/export_png.py`: Playwright PNG üreticisi
- `outputs/preview-all-six-v2.png`: ZIP’ten gelen altı master önizleme görseli
