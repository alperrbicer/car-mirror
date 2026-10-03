#!/usr/bin/env node
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { root, withNativeBuildLock } from './deployment-lib.mjs'

try {
  withNativeBuildLock(() => {
    for (const path of ['.build', 'build/cache', 'build/ModuleCache', 'build/deploy/runs', 'build/app-tests.xcresult']) {
      rmSync(join(root, path), { recursive: true, force: true })
    }
    console.log('Build caches and latest test result removed. Release archives, IPAs, upload records and build counter retained.')
  })
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
}
