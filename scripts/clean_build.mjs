#!/usr/bin/env node
import { cleanProjectBuildOutputs, root, withNativeBuildLock } from './deployment-lib.mjs'

try {
  withNativeBuildLock(() => {
    cleanProjectBuildOutputs()
    console.log('Disposable project build caches and test results removed. Release archives, IPAs, upload records, source fixtures and build counter retained.')
  })
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
}
