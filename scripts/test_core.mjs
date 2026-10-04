#!/usr/bin/env node
import { loadEnvironment, run, withBuildCacheCleanup, withNativeBuildLock } from './deployment-lib.mjs'

const flags = process.argv.slice(2)
try {
  loadEnvironment()
  withNativeBuildLock(() => withBuildCacheCleanup(() => {
    run('xcrun', ['swift', 'test', ...flags.filter(flag => flag !== '--keep-cache')])
  }, { keepCache: flags.includes('--keep-cache') }))
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
}
