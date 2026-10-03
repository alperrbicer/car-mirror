#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
const root = fileURLToPath(new URL('..', import.meta.url))
const device = process.argv[2]
const uiOnly = process.argv[3] === '--ui-only'
if (!device || !/^[0-9a-f-]{36}$/i.test(device) || (process.argv[3] && !uiOnly) || process.argv.length > 4) {
  console.error('Usage: node scripts/test_app.mjs SIMULATOR_UDID [--ui-only]\nUse a working StoreKit Test runtime for purchase tests. --ui-only also works on iOS 26.5.')
  process.exit(1)
}
const results = join(root, 'build', `app-tests-${new Date().toISOString().replaceAll(':', '-')}.xcresult`)
mkdirSync(join(root, 'build'), { recursive: true })
const run = spawnSync('xcodebuild', ['-project', join(root, 'CarMirror.xcodeproj'), '-scheme', 'CarMirror',
  '-configuration', 'Debug', '-parallel-testing-enabled', 'NO', '-jobs', '1', '-destination', `platform=iOS Simulator,id=${device}`,
  '-derivedDataPath', join(root, 'build/app-tests'), '-resultBundlePath', results,
  ...(uiOnly ? ['-only-testing:MirivoUITests'] : []),
  `CODE_SIGN_ENTITLEMENTS=${join(root, 'Config/App.entitlements')}`, 'CODE_SIGN_IDENTITY=-', 'test'], { stdio: 'inherit' })
process.exit(run.status ?? 1)
