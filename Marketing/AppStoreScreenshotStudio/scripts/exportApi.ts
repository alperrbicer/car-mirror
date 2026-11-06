import type { Plugin } from 'vite';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cp, copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const run = promisify(execFile);
const locales = ['tr-TR', 'en-US', 'de-DE'];
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
          if (!['single', 'locale', 'all'].includes(scope)) throw new Error('Unknown export scope');
          if (!locales.includes(locale)) throw new Error('Unsupported locale');
          const selectedLocales = scope === 'all' ? locales : [locale];
          const selectedDevices: Device[] = scope === 'single' ? [requestedDevice] : [...devices];
          const args = ['tools/export_png.py', '--lang', scope === 'all' ? 'all' : locale, '--device', scope === 'single' ? requestedDevice : 'all', '--slide', '1'];
          await run('python3', args, { cwd: server.config.root, maxBuffer: 4 * 1024 * 1024 });
          const files = selectedLocales.flatMap((language) => selectedDevices.map((device) => ({
            name: `01_${language}_${device}.png`,
            url: `/outputs/app-store-screenshots/${language}/${device}/01.png`,
          })));
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
