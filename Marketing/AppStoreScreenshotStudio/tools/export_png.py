#!/usr/bin/env python3
"""Render the supplied Mirivo V2 HTML/CSS masters with Playwright."""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import mimetypes
import re
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFont
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'outputs' / 'app-store-screenshots'
SIZES = {'iphone': (1320, 2868), 'ipad': (2752, 2064)}
MISSING_BY_SLIDE = {
    1: [],
    2: [],
    3: [],
    4: [],
    5: [],
    6: [],
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lang', '--locale', dest='lang', default='all', help='Locale code or all (default: all)')
    parser.add_argument('--device', choices=['iphone', 'ipad', 'all'], default='all')
    parser.add_argument('--slide', type=int, choices=range(1, 7), default=1, help='Master number (default: 1)')
    parser.add_argument('--slides', help='Comma-separated master numbers, for example 1,3,5')
    parser.add_argument('--all-slides', action='store_true', help='Export all six masters for the selected locales and devices')
    parser.add_argument('--all', action='store_true', help='Export all supplied masters, locales, and devices')
    parser.add_argument('--output', default=str(OUTPUT))
    parser.add_argument('--chrome', default=None, help='Optional local Chromium executable path')
    args = parser.parse_args()
    if args.all:
        args.lang, args.device, args.slides = 'all', 'all', '1,2,3,4,5,6'
    if args.slides:
        try:
            slides = sorted({int(value) for value in args.slides.split(',')})
        except ValueError:
            parser.error('--slides must be a comma-separated list of numbers from 1 to 6')
        if not slides or any(slide < 1 or slide > 6 for slide in slides):
            parser.error('--slides must contain one or more numbers from 1 to 6')
    else:
        slides = list(range(1, 7)) if args.all_slides or args.slide is None else [args.slide]
    translation_text = (ROOT / 'translations.js').read_text(encoding='utf-8')
    available = re.findall(r"^\s*['\"]([A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*)['\"]\s*:\s*\[", translation_text, flags=re.MULTILINE)
    if args.lang != 'all' and args.lang not in available:
        parser.error('Unknown locale. Defined locales: ' + ', '.join(available))
    return args, available, slides


def compile_html(slide: int, lang: str, device: str) -> tuple[str, dict[str, str]]:
    html = (ROOT / f'screenshot-{slide:02d}.html').read_text(encoding='utf-8')
    css = (ROOT / 'styles.css').read_text(encoding='utf-8')
    translations = (ROOT / 'translations.js').read_text(encoding='utf-8')
    render = (ROOT / 'render.js').read_text(encoding='utf-8')
    html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>' + css + '</style>')
    html = html.replace('<script src="translations.js"></script>', '<script>' + translations + '</script>')
    html = html.replace('<script src="render.js"></script>', '<script>' + render + '</script>')
    import_script = '<script>window.MIRIVO_RENDER_OPTIONS=' + json.dumps({'lang': lang, 'device': device}) + '</script>'
    assets: dict[str, str] = {}
    for asset in [ROOT / 'assets' / 'MirivoMark.svg', *(ROOT / 'assets' / 'screens').glob('*.png')]:
        if not asset.is_file():
            continue
        mime = mimetypes.guess_type(asset.name)[0] or 'application/octet-stream'
        encoded = base64.b64encode(asset.read_bytes()).decode('ascii')
        assets['logo' if asset.name == 'MirivoMark.svg' else asset.stem] = f'data:{mime};base64,{encoded}'
    asset_script = '<script>window.MIRIVO_ASSETS=' + json.dumps(assets) + ';</script>'
    html = html.replace('<script>' + render + '</script>', asset_script + import_script + '<script>' + render + '</script>')
    return html, assets


def diagnostics(page):
    return page.evaluate('''() => {
      const copy = document.querySelector('.copy');
      const box = copy.getBoundingClientRect();
      const lines = [...document.querySelectorAll('.headline span')];
      const overflows = lines.filter((line) => { const r=line.getBoundingClientRect(); return r.left < box.left-1 || r.right > box.right+1; }).map((line)=>line.innerText);
      const missing = [...document.querySelectorAll('img.actual-screenshot')]
        .filter((image) => !image.complete || !image.naturalWidth)
        .map((image) => image.dataset.screen + '.png');
      const logo = document.getElementById('real-logo');
      return { fontLoaded: document.fonts.check('16px Arial'), missing, overflows,
        logoLoaded: logo.complete && logo.naturalWidth > 0,
        board: {width: document.querySelector('.artboard').offsetWidth, height: document.querySelector('.artboard').offsetHeight} };
    }''')


def save_contact_sheets(rendered, output: Path):
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
    for device in SIZES:
        items = [item for item in rendered if item['device'] == device]
        if not items:
            continue
        columns, thumb_w, thumb_h, gap = 3, 360, 430, 22
        rows = (len(items) + columns - 1) // columns
        sheet = Image.new('RGB', (columns * thumb_w + (columns + 1) * gap, rows * (thumb_h + 36) + (rows + 1) * gap), '#101a1c')
        draw = ImageDraw.Draw(sheet)
        for index, item in enumerate(items):
            x = gap + (index % columns) * (thumb_w + gap)
            y = gap + (index // columns) * (thumb_h + 36 + gap)
            with Image.open(item['path']) as source:
                source = source.convert('RGB')
                source.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
                sheet.paste(source, (x + (thumb_w-source.width)//2, y + (thumb_h-source.height)//2))
            draw.text((x, y + thumb_h + 8), f"{item['locale']} · {item['slide']:02d}", fill='#d6e9e5')
        target = output / f'contact-sheet_{device}.png'
        sheet.save(target, format='PNG', icc_profile=profile, optimize=False, compress_level=9)
        print(target)


def main():
    args, available, slides = parse_args()
    langs = available if args.lang == 'all' else [args.lang]
    devices = list(SIZES) if args.device == 'all' else [args.device]
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
    report = {
        'renderer': 'Playwright over supplied V2 HTML/CSS masters',
        'locales': langs,
        'slides': slides,
        'devices': devices,
        'assets': {'logo': 'assets/MirivoMark.svg', 'presentScreenshots': ['assets/screens/01-phone.png', 'assets/screens/01-tablet.png', 'assets/screens/01-tv.png', 'assets/screens/01-car.png', 'assets/screens/02-phone.png', 'assets/screens/03-tv.png', 'assets/screens/04-car.png', 'assets/screens/05-library.png', 'assets/screens/05-detail.png', 'assets/screens/06-player.png'], 'intentionallyBlankScreens': [], 'missingScreenSlots': []},
        'qualityChecks': {'font': 'pending', 'textOverflow': 'pending', 'dimensions': 'passed', 'opaquePng': 'passed', 'embeddedSrgbProfile': 'passed', 'repeatRenderHash': 'passed'},
        'files': [],
    }
    all_missing: set[str] = set()
    rendered = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, args=['--no-sandbox', '--disable-dev-shm-usage'], **({'executable_path': args.chrome} if args.chrome else {}))
        try:
            for device in devices:
                width, height = SIZES[device]
                page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1, reduced_motion='reduce')
                for lang in langs:
                    for slide in slides:
                        html, _assets = compile_html(slide, lang, device)
                        page.set_content(html, wait_until='load')
                        page.wait_for_function('window.MIRIVO_RENDER_READY === true')
                        page.evaluate('document.fonts.ready')
                        page.wait_for_timeout(120)
                        checks = diagnostics(page)
                        if not checks['fontLoaded']:
                            raise RuntimeError(f'{lang}/{device}/{slide:02d}: required Arial/system font did not resolve')
                        if checks['overflows']:
                            raise RuntimeError(f'{lang}/{device}/{slide:02d}: text overflow: {checks["overflows"]}')
                        if not checks['logoLoaded']:
                            raise RuntimeError('Original logo asset failed to load: assets/MirivoMark.svg')
                        if checks['board'] != {'width': width, 'height': height}:
                            raise RuntimeError(f'{lang}/{device}/{slide:02d}: incorrect artboard dimensions {checks["board"]}')
                        raw = page.screenshot(type='png', animations='disabled')
                        duplicate = page.screenshot(type='png', animations='disabled')
                        first_hash = hashlib.sha256(raw).hexdigest()
                        if first_hash != hashlib.sha256(duplicate).hexdigest():
                            raise RuntimeError(f'{lang}/{device}/{slide:02d}: repeated render was not byte deterministic')
                        image = Image.open(io.BytesIO(raw)).convert('RGB')
                        if image.size != (width, height):
                            raise RuntimeError(f'{lang}/{device}/{slide:02d}: screenshot returned {image.size}')
                        target = output / lang / device / f'{slide:02d}.png'
                        target.parent.mkdir(parents=True, exist_ok=True)
                        image.save(target, format='PNG', icc_profile=srgb, optimize=False, compress_level=9)
                        normalized = target.read_bytes()
                        final_hash = hashlib.sha256(normalized).hexdigest()
                        all_missing.update(checks['missing'])
                        report['qualityChecks']['font'] = 'available'
                        report['qualityChecks']['textOverflow'] = 'passed'
                        report['files'].append({'file': str(target.relative_to(ROOT)), 'bytes': len(normalized), 'sha256': final_hash, 'width': width, 'height': height, 'opaque': True, 'embeddedSrgbProfile': True, 'locale': lang, 'device': device, 'slide': slide})
                        rendered.append({'locale': lang, 'device': device, 'slide': slide, 'path': target})
                        print(f'✓ {target} — {width}×{height}, sRGB, opaque, repeat hash passed')
                page.close()
        finally:
            browser.close()
    report['assets']['missingScreenSlots'] = sorted(all_missing)
    save_contact_sheets(rendered, output)
    report_path = output / 'render-report.json'
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(report_path)


if __name__ == '__main__':
    main()
