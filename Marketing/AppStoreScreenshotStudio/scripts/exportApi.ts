import type { Plugin } from 'vite';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const run = promisify(execFile);
const locales = ['tr-TR', 'en-US', 'de-DE', 'zh-Hans', 'zh-Hant', 'ja-JP', 'ko-KR', 'fr-FR', 'es-ES', 'it-IT', 'pt-BR', 'ru-RU', 'nl-NL', 'pl-PL', 'sv-SE', 'uk-UA', 'ar-SA', 'he-IL', 'th-TH', 'vi-VN', 'id-ID', 'hi-IN'];
const devices = ['iphone', 'ipad'] as const;
type Device = typeof devices[number];

export function exportApi(): Plugin {
  return {
    name: 'mirivo-screenshot-export',
    async closeBundle() {
      const root = process.cwd();
      const output = path.join(root, 'dist');
      await mkdir(output, { recursive: true });
      await Promise.all([
        'styles.css', 'render.js', 'translations.js',
        ...Array.from({ length: 6 }, (_, index) => `screenshot-${String(index + 1).padStart(2, '0')}.html`),
      ].map((file) => copyFile(path.join(root, file), path.join(output, file))));
      await cp(path.join(root, 'assets'), path.join(output, 'assets'), { recursive: true });
      await cp(path.join(root, 'outputs', 'preview-all-six-v2.png'), path.join(output, 'preview-all-six-v2.png'));
    },
    configureServer(server) {
      server.middlewares.use('/api/export', async (req, res) => {
        try {
          const url = new URL(req.url || '/', 'http://localhost');
          const scope = url.searchParams.get('scope') || 'single';
          const locale = url.searchParams.get('locale') || 'tr-TR';
          const requestedDevice = url.searchParams.get('device') === 'ipad' ? 'ipad' : 'iphone';
          const rawSlides = url.searchParams.get('slides') || url.searchParams.get('slide') || '1';
          const requestedSlides = [...new Set(rawSlides.split(',').map(Number))].sort((a, b) => a - b);
          if (!['single', 'locale', 'all', 'all-screens'].includes(scope)) throw new Error('Unknown export scope');
          if (!locales.includes(locale)) throw new Error('Unsupported locale');
          if (requestedSlides.length === 0 || requestedSlides.some((slide) => !Number.isInteger(slide) || slide < 1 || slide > 6)) throw new Error('Unsupported screenshot numbers');
          const selectedLocales = scope === 'all' || scope === 'all-screens' ? locales : [locale];
          const selectedDevices: Device[] = scope === 'single' ? [requestedDevice] : [...devices];
          const args = scope === 'all-screens'
            ? ['tools/export_png.py', '--all']
            : ['tools/export_png.py', '--lang', scope === 'all' ? 'all' : locale, '--device', scope === 'single' ? requestedDevice : 'all', '--slides', requestedSlides.join(',')];
          await run('python3', args, { cwd: server.config.root, maxBuffer: 4 * 1024 * 1024 });
          let files: { name: string; url: string }[];
          const selectedFiles = selectedLocales.flatMap((language) => selectedDevices.flatMap((device) => requestedSlides.map((slide) => ({
            name: `${String(slide).padStart(2, '0')}_${language}_${device}.png`,
            path: `${language}/${device}/${String(slide).padStart(2, '0')}.png`,
            url: `/outputs/app-store-screenshots/${language}/${device}/${String(slide).padStart(2, '0')}.png`,
          }))));
          if (scope === 'all-screens' || requestedSlides.length > 1) {
            const outputRoot = path.join(server.config.root, 'outputs', 'app-store-screenshots');
            const archiveName = scope === 'all-screens'
              ? 'all-languages-all-screens.zip'
              : `selected-${scope}-${scope === 'single' ? `${locale}-${requestedDevice}` : locale}-${requestedSlides.join('-')}.zip`;
            const zipPath = path.join(outputRoot, archiveName);
            const zipScript = `
import sys
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile
source = Path(sys.argv[1]).resolve()
target = Path(sys.argv[2]).resolve()
members = sys.argv[3:]
with ZipFile(target, 'w', compression=ZIP_STORED) as archive:
    if members:
        for member in members:
            item = source / member
            if item.is_file():
                archive.write(item, member)
    else:
        for item in sorted(source.rglob('*')):
            if item.is_file() and item.resolve() != target and (item.suffix.lower() == '.png' or item.name == 'render-report.json'):
                archive.write(item, item.relative_to(source))
`;
            const members = scope === 'all-screens' ? [] : selectedFiles.map((file) => file.path);
            await run('python3', ['-c', zipScript, outputRoot, zipPath, ...members], { cwd: server.config.root, maxBuffer: 4 * 1024 * 1024 });
            files = [{ name: scope === 'all-screens' ? 'mirivo-all-languages-all-screens.zip' : archiveName, url: `/outputs/app-store-screenshots/${archiveName}` }];
          } else {
            files = selectedFiles.map(({ name, url }) => ({ name, url }));
          }
          res.setHeader('Content-Type', 'application/json; charset=utf-8');
          res.end(JSON.stringify({ files }));
        } catch (error) {
          const detail = error instanceof Error ? error.message : String(error);
          res.statusCode = 500;
          res.setHeader('Content-Type', 'text/plain; charset=utf-8');
          res.end(detail);
        }
      });
    },
  };
}
