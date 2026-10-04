#!/usr/bin/env node
import { readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { cleanBuildCaches, root, withNativeBuildLock } from './deployment-lib.mjs'

try {
  withNativeBuildLock(() => {
    cleanBuildCaches()
    for (const path of ['build/deploy/runs', ...readdirSync(join(root, 'build')).filter(name => name.endsWith('.xcresult')).map(name => `build/${name}`)]) {
      rmSync(join(root, path), { recursive: true, force: true })
    }
    console.log('Build caches and latest test result removed. Release archives, IPAs, upload records and build counter retained.')
  })
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
}
