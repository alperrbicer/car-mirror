#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { mkdirSync, rmSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { derivedDataRoot, packageCacheRoot, withBuildCacheCleanup, withNativeBuildLock } from './deployment-lib.mjs'
const root = fileURLToPath(new URL('..', import.meta.url))
const [device, ...flags] = process.argv.slice(2)
const uiOnly = flags.includes('--ui-only')
const selectedTests = flags.filter(flag => flag.startsWith('--only-testing=')).map(flag => flag.slice('--only-testing='.length))
if (!device || !/^[0-9a-f-]{36}$/i.test(device) ||
    flags.some(flag => !['--ui-only', '--keep-cache'].includes(flag) && !/^--only-testing=[A-Za-z_][A-Za-z0-9_]*(?:\/[A-Za-z_][A-Za-z0-9_]*){0,2}$/.test(flag)) ||
    (uiOnly && selectedTests.length > 0)) {
  console.error('Usage: node scripts/test_app.mjs SIMULATOR_UDID [--ui-only | --only-testing=TARGET[/CLASS[/METHOD]]] [--keep-cache]\nUse a working StoreKit Test runtime for purchase tests. --only-testing may be repeated.')
  process.exit(1)
}
const results = join(root, 'build/app-tests.xcresult')
try {
  const status = withNativeBuildLock(() => withBuildCacheCleanup(() => {
    mkdirSync(join(root, 'build'), { recursive: true })
    rmSync(results, { recursive: true, force: true })
    const run = spawnSync('xcodebuild', ['-project', join(root, 'CarMirror.xcodeproj'), '-scheme', 'CarMirror',
      '-configuration', 'Debug', '-parallel-testing-enabled', 'NO', '-jobs', '1', '-destination', `platform=iOS Simulator,id=${device}`,
      '-collect-test-diagnostics', 'never',
      '-derivedDataPath', derivedDataRoot, '-clonedSourcePackagesDirPath', packageCacheRoot, '-resultBundlePath', results,
      `MIRIVO_CRASHLYTICS_DIR=${join(packageCacheRoot, 'checkouts/firebase-ios-sdk/Crashlytics')}`,
      ...(uiOnly ? ['-only-testing:MirivoUITests'] : []),
      ...selectedTests.map(test => `-only-testing:${test}`),
      `MIRIVO_MAIN_APP_ENTITLEMENTS=${join(root, 'Config/App.entitlements')}`,
      // Simulator purchase tests use local StoreKit only, without RevenueCat sync.
      'MIRIVO_REVENUECAT_API_KEY=', 'CODE_SIGN_IDENTITY=-', 'test'], { stdio: 'inherit' })
    return run.status ?? 1
  }, { keepCache: flags.includes('--keep-cache') }))
  process.exitCode = status
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
}
