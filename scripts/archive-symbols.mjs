import { existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { run } from './deployment-lib.mjs'

// Xcode embeds these static SDKs' resources in frameworks with an empty dylib.
// The SDK code is in the app; only the generated resource stub lacks a dSYM.
const resourceStubs = ['FirebaseAnalytics', 'GoogleAppMeasurement', 'GoogleCast']

export function isEmptyResourceStub(loadCommands) {
  const sections = [...loadCommands.matchAll(/sectname\s+(\S+)[\s\S]*?\bsize\s+(0x[\da-f]+)/gi)]
  const symbolCounts = [...loadCommands.matchAll(/\bnsyms\s+(\d+)/g)]
  return /\bcmd LC_ID_DYLIB\b/.test(loadCommands) && sections.length > 0 &&
    sections.every(([, name, size]) => name === '__text' && BigInt(size) === 0n) &&
    symbolCounts.length > 0 && symbolCounts.every(([, count]) => count === '0')
}

export function symbolUUIDs(output) {
  return [...output.matchAll(/UUID: ([\dA-F-]+) \(([^)]+)\)/gi)]
    .map(([, uuid, arch]) => `${uuid.toUpperCase()}:${arch}`).sort()
}

export function completeArchiveStubSymbols(archive) {
  const dsymRoot = join(archive, 'dSYMs')
  for (const name of resourceStubs) {
    const binary = join(archive, 'Products/Applications/CarMirror.app/Frameworks', `${name}.framework`, name)
    if (!existsSync(binary)) continue
    const output = join(dsymRoot, `${name}.framework.dSYM`)
    if (!existsSync(output)) {
      const commands = run('xcrun', ['otool', '-l', binary], { capture: true, quiet: true })
      if (!isEmptyResourceStub(commands)) {
        throw new Error(`${name}: missing vendor dSYM for a nonempty binary; refusing to create placeholder symbols.`)
      }
      mkdirSync(dsymRoot, { recursive: true })
      // An empty debug table is correct only for this verified zero-code stub.
      run('xcrun', ['dsymutil', binary, '-o', output], { capture: true, quiet: true })
    }
    const binaryUUIDs = symbolUUIDs(run('xcrun', ['dwarfdump', '--uuid', binary], { capture: true, quiet: true }))
    const dsymUUIDs = symbolUUIDs(run('xcrun', ['dwarfdump', '--uuid', output], { capture: true, quiet: true }))
    if (!binaryUUIDs.length || JSON.stringify(binaryUUIDs) !== JSON.stringify(dsymUUIDs)) {
      throw new Error(`${name}: archive binary and dSYM UUIDs do not match.`)
    }
    console.log(`Verified resource-stub symbols: ${name} (${binaryUUIDs.join(', ')})`)
  }
}
