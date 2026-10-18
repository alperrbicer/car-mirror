import test from 'node:test'
import { isEmptyResourceStub, symbolUUIDs } from '../../scripts/archive-symbols.mjs'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  argumentsFor, assertCarPlayVideo, configurationFromSettings, exportPlist, parsePlist, parseProfile, keepBuildCache,
  physicalPhones, reserveBuild, root, runDirectory, selectDevice, validateProfile, withBuildCacheCleanup, withNativeBuildLock,
} from '../../scripts/deployment-lib.mjs'

const team = 'TEAM123456'
test('daily installs retain incremental caches with an explicit cleanup override', () => {
  for (const command of ['install', 'simulator']) {
    assert.equal(keepBuildCache(argumentsFor([command])), true)
    assert.equal(keepBuildCache(argumentsFor([command, '--clean-cache'])), false)
  }
  for (const command of ['check', 'archive', 'upload', 'testflight']) {
    assert.equal(keepBuildCache(argumentsFor([command])), false)
    assert.equal(keepBuildCache(argumentsFor([command, '--keep-cache'])), true)
  }
  assert.throws(() => argumentsFor(['install', '--keep-cache', '--clean-cache']), /either/)
})
test('archive symbol completion accepts only empty resource dylibs', () => {
  const stub = 'cmd LC_ID_DYLIB\nsectname __text\nsegname __TEXT\nsize 0x00000000\nnsyms 0'
  assert.equal(isEmptyResourceStub(stub), true)
  assert.equal(isEmptyResourceStub(stub.replace('0x00000000', '0x00000004')), false)
  assert.equal(isEmptyResourceStub(stub.replace('nsyms 0', 'nsyms 1')), false)
  assert.equal(isEmptyResourceStub(stub.replace('__text', '__data')), false)
  assert.equal(isEmptyResourceStub(stub.replace('LC_ID_DYLIB', 'LC_LOAD_DYLIB')), false)
  assert.equal(isEmptyResourceStub(''), false)
  assert.equal(isEmptyResourceStub(stub + '\nsectname __text\nsize 0x10\nnsyms 0'), false)
  assert.deepEqual(symbolUUIDs('UUID: ab12-CD34 (arm64) /tmp/file'), ['AB12-CD34:arm64'])
})
const bundleId = 'com.example.carmirror'
const appGroup = `group.${bundleId}`
const config = { bundleId, appGroup, team, mainApp: true, now: Date.UTC(2026, 0, 1) }
const settings = { PRODUCT_BUNDLE_IDENTIFIER: bundleId, APP_GROUP_IDENTIFIER: appGroup,
  DEVELOPMENT_TEAM: team, MARKETING_VERSION: '0.1.0', CURRENT_PROJECT_VERSION: '3', CODE_SIGN_ENTITLEMENTS: 'Config/App.entitlements' }

function signing() {
  const entitlements = { 'application-identifier': `${team}.${bundleId}`, 'com.apple.developer.team-identifier': team,
    'aps-environment': 'production', 'com.apple.developer.devicecheck.appattest-environment': 'production',
    'com.apple.security.application-groups': [appGroup], 'com.apple.developer.carplay-video': true, 'com.apple.developer.carplay-audio': true }
  return { entitlements, profile: { Entitlements: structuredClone(entitlements), TeamIdentifier: [team],
    ApplicationIdentifierPrefix: [team], ExpirationDate: '2027-01-01T00:00:00Z' } }
}

function phone(identifier = 'core-id', udid = 'phone-udid', name = 'My iPhone') {
  return { identifier, hardwareProperties: { reality: 'physical', productType: 'iPhone18,1', udid },
    connectionProperties: { pairingState: 'paired' }, deviceProperties: { name } }
}

test('push profiles must match the signature and distribution must use production APNs', () => {
  for (const field of ['aps-environment', 'com.apple.developer.devicecheck.appattest-environment']) {
    const fixture = signing()
    delete fixture.profile.Entitlements[field]
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /Push Notifications|App Attest/)
  }
  const development = signing()
  development.entitlements['aps-environment'] = 'development'
  development.profile.Entitlements['aps-environment'] = 'development'
  validateProfile(development.entitlements, development.profile, config)
  assert.throws(() => validateProfile(development.entitlements, development.profile, { ...config, distribution: true }), /production APNs/)
})

test('Apple App Attest profile arrays must explicitly permit production', () => {
  const key = 'com.apple.developer.devicecheck.appattest-environment'
  for (const grant of [['development', 'production'], ['production'], ['*']]) {
    const fixture = signing()
    fixture.profile.Entitlements[key] = grant
    validateProfile(fixture.entitlements, fixture.profile, config)
  }
  for (const grant of [['development'], [], ['production-invalid'], true, null]) {
    const fixture = signing()
    fixture.profile.Entitlements[key] = grant
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /App Attest/)
  }
  const fixture = signing()
  fixture.profile.Entitlements[key] = ['development', 'production']
  fixture.entitlements[key] = 'development'
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /App Attest/)
})

function temporary(t) {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), 'carmirror-deployment-test-')))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  return directory
}

test('Crashlytics uploads only Release device symbols and propagates SDK failures', t => {
  const directory = temporary(t)
  const sdk = join(directory, 'SDK with spaces'); mkdirSync(sdk)
  const log = join(directory, 'uploader.log')
  const uploader = join(sdk, 'upload-symbols')
  writeFileSync(uploader, '#!/bin/sh\necho "$*" >> "$TEST_UPLOAD_LOG"\ncase "$*" in *--validate*) exit "${TEST_VALIDATE_STATUS:-0}";; *) exit "${TEST_UPLOAD_STATUS:-0}";; esac\n')
  chmodSync(uploader, 0o755)
  const env = { ...process.env, MIRIVO_CRASHLYTICS_DIR: sdk, TEST_UPLOAD_LOG: log }
  const invoke = overrides => spawnSync('/bin/sh', [join(root, 'scripts/upload-crashlytics-symbols.sh')], {
    env: { ...env, CONFIGURATION: 'Release', PLATFORM_NAME: 'iphoneos', ...overrides }, encoding: 'utf8',
  })
  for (const overrides of [{ CONFIGURATION: 'Debug' }, { PLATFORM_NAME: 'iphonesimulator' }]) {
    assert.equal(invoke(overrides).status, 0)
    assert.equal(existsSync(log), false, 'Debug and simulator builds must never invoke the SDK uploader')
  }
  assert.equal(invoke({}).status, 0)
  assert.equal(readFileSync(log, 'utf8'), '--build-phase --validate\n--build-phase\n')
  writeFileSync(log, '')
  assert.equal(invoke({ TEST_VALIDATE_STATUS: '17' }).status, 17)
  assert.equal(readFileSync(log, 'utf8'), '--build-phase --validate\n', 'validation failure must stop upload')
  assert.equal(invoke({ TEST_UPLOAD_STATUS: '18' }).status, 18, 'upload failure must fail the Release build')
  assert.equal(invoke({ MIRIVO_CRASHLYTICS_DIR: join(directory, 'missing') }).status, 1)
})

function isolatedCLI(t) {
  const directory = temporary(t)
  mkdirSync(join(directory, 'Config'))
  writeFileSync(join(directory, 'Config/Base.xcconfig'), 'CURRENT_PROJECT_VERSION = 3\n')
  mkdirSync(join(directory, 'scripts'))
  for (const file of ['ios.mjs', 'deployment-lib.mjs', 'archive-symbols.mjs', 'test_app.mjs', 'test_core.mjs', 'clean_build.mjs']) copyFileSync(join(root, 'scripts', file), join(directory, 'scripts', file))
  return { directory, script: join(directory, 'scripts/ios.mjs'), env: { ...process.env, MIRROR_TEAM_ID: '',
    APP_STORE_CONNECT_KEY_ID: '', APP_STORE_CONNECT_ISSUER_ID: '', APP_STORE_CONNECT_PRIVATE_KEY_PATH: '' } }
}

test('Xcode 27.1 physical iPhones without reality retain hardware identification', () => {
  const physical = phone()
  delete physical.hardwareProperties.reality
  physical.hardwareProperties.ecid = 4047173700321308
  physical.hardwareProperties.udid = '00008140-000E60E20EC0801C'
  const simulator = structuredClone(physical)
  simulator.hardwareProperties.reality = 'simulated'
  simulator.hardwareProperties.udid = 'B952AA0F-C81F-49A2-83F3-CEBE9D048739'
  const unidentified = structuredClone(simulator)
  delete unidentified.hardwareProperties.reality
  assert.deepEqual(physicalPhones({result: {devices: [physical, simulator, unidentified]}}).map(device => device.udid), [physical.hardwareProperties.udid])
})

test('CLI rejects ambiguous or incompatible arguments before doing work', () => {
  assert.equal(argumentsFor(['install', '--', 'My iPhone']).device, 'My iPhone')
  assert.equal(argumentsFor(['install', '--preview']).preview, true)
  for (const command of ['doctor', 'devices', 'check', 'prepare', 'simulator', 'archive', 'export', 'upload', 'testflight']) {
    assert.throws(() => argumentsFor([command, '--preview']), /--preview does not apply/)
  }
  assert.equal(argumentsFor(['archive', '--build', '15', '--version', '1.2.3']).build, '15')
  for (const args of [['android'], ['install', '--device'], ['install', '--device', ''], ['install', 'one', 'two'],
    ['install', 'one', '--device', 'two'], ['archive', '--build', '0'], ['archive', '--version', '1.x'],
    ['upload', '--archive', '/a', '--build', '5'], ['export', '--version', '1.0'], ['check', '--device', 'one'], ['archive', '--skip-tests']]) {
    assert.throws(() => argumentsFor(args), undefined, args.join(' '))
  }
})

test('device discovery handles both schemas and never selects a Watch or an ambiguous iPhone', () => {
  const newer = { identifier: 'second-core-id', properties: { hardware: { reality: 'physical', deviceType: 'iPhone', udid: 'second-udid' },
    connection: { pairingState: 'paired' }, state: { name: 'Second iPhone' } } }
  const watch = phone('watch', 'watch-udid', 'Watch'); watch.hardwareProperties.productType = 'Watch7,1'
  const unpaired = phone('third'); unpaired.connectionProperties.pairingState = 'unpaired'
  const list = physicalPhones({ result: { devices: [phone(), newer, watch, unpaired] } })
  assert.equal(list.length, 2)
  assert.throws(() => selectDevice(list), /Multiple/)
  assert.equal(selectDevice(list, 'SECOND-UDID').id, 'second-core-id')
  assert.equal(selectDevice(list, 'My iPhone').udid, 'phone-udid')
  assert.throws(() => selectDevice(list, 'Watch'), /No matching/)
  assert.throws(() => selectDevice([]), /No matching/)
  // Xcode may emit both formats while retiring the legacy dictionaries.
  const mixed = { ...phone(), identifier: newer.identifier, properties: newer.properties }
  assert.deepEqual(physicalPhones({ result: { devices: [mixed] } }), [list[1]])
})

test('signed app and profile must both retain App Group and identity', () => {
  const good = signing()
  validateProfile(good.entitlements, good.profile, config)
  for (const source of ['entitlements', 'profile']) for (const key of ['com.apple.security.application-groups', 'application-identifier']) {
    const fixture = signing()
    delete (source === 'profile' ? fixture.profile.Entitlements : fixture.entitlements)[key]
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), undefined, `${source}: ${key}`)
  }
})

test('profile checks reject expired, foreign-team, unregistered-device and non-App-Store profiles', () => {
  for (const change of [fixture => { fixture.profile.ExpirationDate = '2020-01-01' },
    fixture => { fixture.profile.TeamIdentifier = ['OTHERTEAM0'] }, fixture => { fixture.entitlements['com.apple.developer.team-identifier'] = 'OTHERTEAM0' }]) {
    const fixture = signing(); change(fixture)
    assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config))
  }
  const fixture = signing()
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, device: 'my-udid' }), /selected iPhone/)
  fixture.profile.ProvisionedDevices = ['MY-UDID']
  validateProfile(fixture.entitlements, fixture.profile, { ...config, device: 'my-udid' })
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
  delete fixture.profile.ProvisionedDevices
  fixture.profile.Entitlements['get-task-allow'] = true
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
  delete fixture.profile.Entitlements['get-task-allow']
  fixture.profile.ProvisionsAllDevices = true
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...config, distribution: true }), /App Store/)
})

test('explicit iPhone preview retains the CarPlay Video profile and signing checks', () => {
  const fixture = signing()
  fixture.profile.ProvisionedDevices = ['my-udid']
  const preview = { ...config, preview: true, device: 'my-udid' }
  validateProfile(fixture.entitlements, fixture.profile, preview)
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...preview, distribution: true }), /App Store/)
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, { ...preview, device: 'another-device' }), /selected iPhone/)
  for (const change of [
    item => { delete item.entitlements['com.apple.security.application-groups'] },
    item => { delete item.profile.Entitlements['com.apple.security.application-groups'] },
    item => { item.profile.ExpirationDate = '2020-01-01' },
    item => { item.profile.TeamIdentifier = ['OTHERTEAM0'] },
    item => { item.entitlements['application-identifier'] = `${team}.another-app` },
  ]) {
    const invalid = structuredClone(fixture); change(invalid)
    assert.throws(() => validateProfile(invalid.entitlements, invalid.profile, preview))
  }
})

test('broadcast extension needs its own identity/group, and legacy App ID prefixes are supported', () => {
  const fixture = signing()
  fixture.profile.ApplicationIdentifierPrefix = ['OLDPREFIX0']
  for (const values of [fixture.entitlements, fixture.profile.Entitlements]) {
    delete values['com.apple.developer.carplay-audio']; delete values['com.apple.developer.carplay-video']
    delete values['aps-environment']; delete values['com.apple.developer.devicecheck.appattest-environment']
    values['application-identifier'] = `OLDPREFIX0.${bundleId}.broadcast`
  }
  const extension = { ...config, bundleId: `${bundleId}.broadcast`, mainApp: false }
  validateProfile(fixture.entitlements, fixture.profile, extension)
  delete fixture.entitlements['com.apple.security.application-groups']
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, extension), /App Group/)
})

test('Xcode settings with a zero-exit error or unresolved/missing signing fields are rejected', () => {
  assert.equal(configurationFromSettings([{ target: 'CarMirror', buildSettings: settings }]).team, team)
  assert.throws(() => configurationFromSettings([{ target: 'CarMirror', buildSettings: {}, error: 'PIFCache failed' }]), /PIFCache/)
  assert.throws(() => configurationFromSettings([{ target: 'CarMirror', buildSettings: { ...settings, APP_GROUP_IDENTIFIER: 'group.$(MIRROR_BUNDLE_ID)' } }]), /resolve/)
  assert.throws(() => configurationFromSettings([{ target: 'CarMirror', buildSettings: { ...settings, CODE_SIGN_ENTITLEMENTS: 'Config/CarPlayAudio.entitlements' } }]), /CarPlay/)
})

test('build reservations increase across runs without changing source and refuse corrupt/locked state', t => {
  const directory = temporary(t)
  assert.equal(reserveBuild('3', undefined, directory), '4')
  assert.equal(reserveBuild('3', undefined, directory), '5')
  assert.equal(reserveBuild('3', '12', directory), '12')
  assert.equal(reserveBuild('3', '8', directory), '8')
  assert.equal(reserveBuild('3', undefined, directory), '13')
  writeFileSync(join(directory, '.build-number.lock'), '')
  assert.throws(() => reserveBuild('3', undefined, directory), /Another archive/)
  rmSync(join(directory, '.build-number.lock'))
  writeFileSync(join(directory, 'last-build.json'), '{"build":"invalid"}')
  assert.throws(() => reserveBuild('3', undefined, directory), /Invalid local/)
  assert.equal(existsSync(join(directory, '.build-number.lock')), false)
})

test('Apple plist handling accepts dates/certificates and export preserves the chosen build number', { skip: process.platform !== 'darwin' }, () => {
  const xml = `<?xml version="1.0"?><plist version="1.0"><dict>
    <key>DeveloperCertificates</key><array><data>YWJj</data></array>
    <key>ExpirationDate</key><date>2027-01-01T00:00:00Z</date>
    <key>Entitlements</key><dict><key>get-task-allow</key><false/></dict>
    <key>TeamIdentifier</key><array><string>${team}</string></array>
    <key>ProvisionedDevices</key><array><string>my-udid</string></array>
  </dict></plist>`
  const profile = parseProfile(xml)
  assert.equal(profile.ExpirationDate, '2027-01-01T00:00:00Z')
  assert.deepEqual(profile.ProvisionedDevices, ['my-udid'])
  assert.equal(profile.Entitlements['get-task-allow'], false)
  const plist = parsePlist(exportPlist(team, 'upload'))
  assert.equal(plist.method, 'app-store-connect')
  assert.equal(plist.destination, 'upload')
  assert.equal(plist.manageAppVersionAndBuildNumber, false)
})

test('every dry run works from another directory without native tools, credentials or writes', t => {
  const fixture = isolatedCLI(t)
  const env = { ...fixture.env, PATH: '/nonexistent' }
  for (const command of ['doctor', 'devices', 'check', 'prepare', 'install', 'simulator', 'archive', 'export', 'upload', 'testflight']) {
    const result = spawnSync(process.execPath, [fixture.script, command, '--dry-run'], { cwd: tmpdir(), env, encoding: 'utf8' })
    assert.equal(result.status, 0, `${command}: ${result.stderr}`)
    assert.equal(existsSync(join(fixture.directory, 'build')), false, command)
  }
  const upload = spawnSync(process.execPath, [fixture.script, 'upload', '--archive', '/a path/archive.xcarchive', '--dry-run'], { env, encoding: 'utf8' })
  assert.equal(upload.status, 0, upload.stderr)
  assert.ok(!upload.stdout.includes('"swift" "test"'), 'existing archive must not rebuild')
})

test('native commands reuse the same build and dependency caches', t => {
  const fixture = isolatedCLI(t)
  for (const command of ['install', 'simulator', 'archive', 'check']) {
    const result = spawnSync(process.execPath, [fixture.script, command, '--dry-run'], {
      env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8',
    })
    assert.equal(result.status, 0, result.stderr)
    assert.ok(result.stdout.includes(JSON.stringify(join(fixture.directory, 'build/cache/DerivedData'))))
    assert.ok(result.stdout.includes(JSON.stringify(join(fixture.directory, 'build/cache/SourcePackages'))))
    assert.ok(result.stdout.includes(`MIRIVO_CRASHLYTICS_DIR=${join(fixture.directory, 'build/cache/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics')}`))
    assert.ok(!result.stdout.includes('/<install>/DerivedData'))
  }
})

test('operational runs replace old records while release archives remain distinct', t => {
  const directory = temporary(t)
  const archive = runDirectory('archive', false, directory)
  writeFileSync(join(archive, 'release'), 'keep')
  const first = runDirectory('install', false, directory)
  writeFileSync(join(first, 'old.json'), '{}')
  assert.equal(runDirectory('install', false, directory), first)
  assert.equal(existsSync(join(first, 'old.json')), false)
  assert.notEqual(runDirectory('archive', false, directory), archive)
  assert.equal(readFileSync(join(archive, 'release'), 'utf8'), 'keep')
})

test('shared cache lock refuses overlapping commands and releases after failures', t => {
  const directory = temporary(t)
  withNativeBuildLock(() => {
    assert.throws(() => withNativeBuildLock(() => assert.fail('must not run'), { directory }), /Another native command/)
  }, { directory })
  assert.throws(() => withNativeBuildLock(() => { throw new Error('build failed') }, { directory }), /build failed/)
  assert.equal(existsSync(join(directory, '.native-build.lock')), false)
  assert.equal(withNativeBuildLock(() => 'ready', { directory }), 'ready')
})

test('build caches are removed after success or failure without deleting release or report files', t => {
  const directory = temporary(t)
  const retained = ['build/deploy/release/App.ipa', 'build/deploy/last-build.json', 'build/app-tests.xcresult/report']
  for (const path of retained) {
    mkdirSync(join(directory, path, '..'), { recursive: true })
    writeFileSync(join(directory, path), 'keep')
  }
  for (const fail of [false, true]) {
    const action = () => {
      for (const path of ['.build', 'build/cache/SourcePackages', 'build/ModuleCache']) {
        mkdirSync(join(directory, path), { recursive: true })
        writeFileSync(join(directory, path, 'artifact'), 'large')
      }
      if (fail) throw new Error('native failed')
      return 17
    }
    if (fail) assert.throws(() => withBuildCacheCleanup(action, { projectRoot: directory }), /native failed/)
    else assert.equal(withBuildCacheCleanup(action, { projectRoot: directory }), 17)
    for (const path of ['.build', 'build/cache', 'build/ModuleCache']) assert.equal(existsSync(join(directory, path)), false)
    for (const path of retained) assert.equal(readFileSync(join(directory, path), 'utf8'), 'keep')
  }
})

test('cache retention is explicit and dry runs never delete existing caches', t => {
  assert.equal(argumentsFor(['install', '--keep-cache'])['keep-cache'], true)
  const directory = temporary(t)
  mkdirSync(join(directory, 'build/cache'), { recursive: true })
  writeFileSync(join(directory, 'build/cache/artifact'), 'keep')
  for (const options of [{ keepCache: true }, { dryRun: true }]) {
    withBuildCacheCleanup(() => {}, { projectRoot: directory, ...options })
    assert.equal(readFileSync(join(directory, 'build/cache/artifact'), 'utf8'), 'keep')
  }
})

test('core test entry point cleans compiler output by default and preserves it only on request', t => {
  const fixture = isolatedCLI(t)
  const binaries = join(fixture.directory, 'bin'); mkdirSync(binaries)
  const fake = join(binaries, 'xcrun')
  writeFileSync(fake, `#!${process.execPath}
import {mkdirSync, writeFileSync} from 'node:fs';
mkdirSync('.build', {recursive:true}); writeFileSync('.build/artifact','large');
`)
  chmodSync(fake, 0o755)
  for (const flags of [[], ['--keep-cache']]) {
    const result = spawnSync(process.execPath, [join(fixture.directory, 'scripts/test_core.mjs'), ...flags], {
      env: { ...fixture.env, PATH: binaries }, encoding: 'utf8',
    })
    assert.equal(result.status, 0, result.stderr)
    assert.equal(existsSync(join(fixture.directory, '.build/artifact')), flags.length > 0)
  }
})

test('clean removes caches while retaining release files and the build counter', t => {
  const fixture = isolatedCLI(t)
  const disposable = ['.build/cache', 'build/cache/SourcePackages/artifact', 'build/ModuleCache/module', 'build/pro-tests-fresh.xcresult/report',
    'build/deploy/runs/install/install.json', 'build/app-tests.xcresult/result']
  const retained = ['build/deploy/last-build.json', 'build/deploy/latest-archive.json',
    'build/deploy/release/CarMirror.xcarchive/archive', 'build/deploy/release/CarMirror.ipa', 'build/deploy/upload.json']
  for (const path of [...disposable, ...retained]) {
    mkdirSync(join(fixture.directory, path, '..'), { recursive: true })
    writeFileSync(join(fixture.directory, path), 'keep')
  }
  const result = spawnSync(process.execPath, [join(fixture.directory, 'scripts/clean_build.mjs')], { encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  for (const path of disposable) assert.equal(existsSync(join(fixture.directory, path)), false, path)
  for (const path of retained) assert.equal(readFileSync(join(fixture.directory, path), 'utf8'), 'keep', path)
})

test('app test entry point replaces its previous report and uses shared caches', t => {
  const fixture = isolatedCLI(t)
  const binaries = join(fixture.directory, 'bin'); mkdirSync(binaries)
  const fake = join(binaries, 'xcodebuild')
  const log = join(fixture.directory, 'args.json')
  writeFileSync(fake, `#!${process.execPath}
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const args = process.argv.slice(2);
writeFileSync(process.env.TEST_ARGS, JSON.stringify(args));
const result = args[args.indexOf('-resultBundlePath') + 1];
mkdirSync(result, { recursive: true });
writeFileSync(join(result, 'new'), 'result');
`)
  chmodSync(fake, 0o755)
  const results = join(fixture.directory, 'build/app-tests.xcresult')
  mkdirSync(results, { recursive: true }); writeFileSync(join(results, 'old'), 'old')
  const result = spawnSync(process.execPath, [join(fixture.directory, 'scripts/test_app.mjs'),
    '00000000-0000-0000-0000-000000000001', '--ui-only'], {
    env: { ...fixture.env, PATH: binaries, TEST_ARGS: log }, encoding: 'utf8',
  })
  assert.equal(result.status, 0, result.stderr)
  assert.equal(existsSync(join(results, 'old')), false)
  assert.equal(existsSync(join(results, 'new')), true)
  const args = JSON.parse(readFileSync(log, 'utf8'))
  assert.equal(args[args.indexOf('-derivedDataPath') + 1], join(fixture.directory, 'build/cache/DerivedData'))
  assert.equal(args[args.indexOf('-clonedSourcePackagesDirPath') + 1], join(fixture.directory, 'build/cache/SourcePackages'))
  assert.ok(args.includes(`MIRIVO_CRASHLYTICS_DIR=${join(fixture.directory, 'build/cache/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics')}`))
  assert.ok(args.includes('-only-testing:MirivoUITests'))
  assert.ok(args.includes('MIRIVO_REVENUECAT_API_KEY='), 'Simulator tests must not sync purchases to RevenueCat')

  const focused = spawnSync(process.execPath, [join(fixture.directory, 'scripts/test_app.mjs'),
    '00000000-0000-0000-0000-000000000001', '--only-testing=MirivoTests/CarConnectionReminderTests', '--keep-cache'], {
    env: { ...fixture.env, PATH: binaries, TEST_ARGS: log }, encoding: 'utf8',
  })
  assert.equal(focused.status, 0, focused.stderr)
  const focusedArgs = JSON.parse(readFileSync(log, 'utf8'))
  assert.ok(focusedArgs.includes('-only-testing:MirivoTests/CarConnectionReminderTests'))
  assert.ok(!focusedArgs.includes('-only-testing:MirivoUITests'))
  assert.equal(focusedArgs[focusedArgs.indexOf('-parallel-testing-enabled') + 1], 'NO')
  assert.equal(focusedArgs[focusedArgs.indexOf('-jobs') + 1], '1')
  assert.equal(focusedArgs[focusedArgs.indexOf('-collect-test-diagnostics') + 1], 'never')

  for (const flags of [
    ['--only-testing='],
    ['--only-testing=MirivoTests/CarConnectionReminderTests', '--ui-only'],
  ]) {
    const invalid = spawnSync(process.execPath, [join(fixture.directory, 'scripts/test_app.mjs'),
      '00000000-0000-0000-0000-000000000001', ...flags], {
      env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8',
    })
    assert.equal(invalid.status, 1)
    assert.match(invalid.stderr, /Usage:/)
  }
})

test('upload with missing API credentials fails before creating build output or running Xcode', t => {
  const fixture = isolatedCLI(t)
  const result = spawnSync(process.execPath, [fixture.script, 'upload'], { env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8' })
  assert.equal(result.status, 1)
  assert.match(result.stderr, process.platform === 'darwin' ? /APP_STORE_CONNECT_KEY_ID/ : /macOS/)
  assert.equal(existsSync(join(fixture.directory, 'build')), false)
})

test('simulator installation retains App Group entitlements through ad hoc signing without provisioning', t => {
  const fixture = isolatedCLI(t)
  const result = spawnSync(process.execPath, [fixture.script, 'simulator', '--dry-run'], {
    env: { ...fixture.env, PATH: '/nonexistent' }, encoding: 'utf8',
  })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /CODE_SIGNING_ALLOWED=YES/)
  assert.match(result.stdout, /CODE_SIGN_IDENTITY=-/)
  assert.ok(!result.stdout.includes('-allowProvisioningUpdates'))
  assert.ok(result.stdout.indexOf('"install"') < result.stdout.indexOf('"launch"'))
})

test('preview overrides only the install entitlements and preserves device signing and verification', t => {
  const fixture = isolatedCLI(t)
  const env = { ...fixture.env, PATH: '/nonexistent' }
  const result = spawnSync(process.execPath, [fixture.script, 'install', '--preview', '--allow-provisioning-updates', '--dry-run'], { env, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  assert.match(result.stdout, /CarPlay Video is enabled/)
  assert.match(result.stdout, /App Groups and standalone iPhone profiles/)
  assert.match(result.stdout, /-allowProvisioningUpdates/)
  assert.ok(!result.stdout.includes('CODE_SIGNING_ALLOWED=NO'))
  assert.ok(result.stdout.indexOf('Verify signature') < result.stdout.indexOf('"install" "app"'))
  assert.ok(result.stdout.indexOf('"install" "app"') < result.stdout.indexOf('"process" "launch"'))
  assert.equal(existsSync(join(fixture.directory, 'build')), false)
  const standard = spawnSync(process.execPath, [fixture.script, 'install', '--dry-run'], { env, encoding: 'utf8' })
  assert.equal(standard.status, 0, standard.stderr)
  assert.ok(!standard.stdout.includes('CODE_SIGN_ENTITLEMENTS='))
  assert.match(standard.stdout, /standalone iPhone profiles/)
  assert.ok(!result.stdout.includes('MIRIVO_CARPLAY_'))
})

test('a failed native build or ambiguous device never reaches installation or launch', { skip: process.platform !== 'darwin' }, t => {
  const fixture = isolatedCLI(t)
  const binaries = join(fixture.directory, 'bin'); mkdirSync(binaries)
  const log = join(fixture.directory, 'commands.jsonl')
  const fake = join(binaries, 'fake.mjs')
  writeFileSync(fake, `#!${process.execPath}
import { appendFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
const args = process.argv.slice(2), command = basename(process.argv[1]);
appendFileSync(process.env.TEST_COMMAND_LOG, JSON.stringify({command, args}) + '\\n');
if (command === 'xcodebuild' && args.includes('-showBuildSettings')) console.log(JSON.stringify([{target:'CarMirror',buildSettings:${JSON.stringify(settings)}}]));
else if (command === 'xcodebuild') process.exit(17);
else if (command === 'xcrun' && args.includes('list') && args.includes('devices')) {
 const devices = [${JSON.stringify(phone())}];
 if (process.env.TEST_AMBIGUOUS) devices.push(${JSON.stringify(phone('second', 'second-udid', 'Second iPhone'))});
 writeFileSync(args[args.indexOf('--json-output')+1], JSON.stringify({result:{devices}}));
} else process.exit(99);
`)
  chmodSync(fake, 0o755)
  for (const command of ['xcodebuild', 'xcrun']) symlinkSync(fake, join(binaries, command))
  const env = { ...fixture.env, PATH: binaries, TEST_COMMAND_LOG: log }
  let calls
  for (const flags of [[], ['--preview']]) {
    writeFileSync(log, '')
    const failed = spawnSync(process.execPath, [fixture.script, 'install', ...flags], { env, encoding: 'utf8' })
    assert.equal(failed.status, 1)
    assert.match(failed.stderr, /17/)
    calls = readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse)
    const build = calls.find(call => call.command === 'xcodebuild' && call.args.includes('build'))
    assert.ok(build)
    const expectedBuild = flags.length ? '5' : '4'
    assert.ok(build.args.includes(`CURRENT_PROJECT_VERSION=${expectedBuild}`))
    assert.match(readFileSync(join(fixture.directory, 'Config/Base.xcconfig'), 'utf8'), new RegExp(`CURRENT_PROJECT_VERSION = ${expectedBuild}`))
    assert.equal(build.args.includes('MIRIVO_MAIN_APP_ENTITLEMENTS=Config/App.entitlements'), false)
    assert.ok(!calls.some(call => call.args.includes('install') || call.args.includes('launch')))
  }
  writeFileSync(log, '')
  const ambiguous = spawnSync(process.execPath, [fixture.script, 'install'], { env: { ...env, TEST_AMBIGUOUS: '1' }, encoding: 'utf8' })
  assert.equal(ambiguous.status, 1)
  assert.match(ambiguous.stderr, /Multiple devices/)
  calls = readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse)
  assert.ok(!calls.some(call => call.args.includes('build') || call.args.includes('install') || call.args.includes('launch')))
})

test('release requires a CarPlay Video scene and Audio and Video signing', () => {
  const scene = { UIApplicationSceneManifest: { UISceneConfigurations: {
    CPTemplateApplicationSceneSessionRoleApplication: [{ UISceneClassName: 'CPTemplateApplicationScene' }],
  } } }
  assertCarPlayVideo(scene)
  assert.throws(() => assertCarPlayVideo({}), /Video scene/)
  assert.throws(() => assertCarPlayVideo({ ...scene, CMCarPlayAudioEnabled: 'YES' }), /Video scene/)
  const fixture = signing()
  validateProfile(fixture.entitlements, fixture.profile, config)
  delete fixture.profile.Entitlements['com.apple.developer.carplay-video']
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /CarPlay Video/)
  fixture.profile.Entitlements['com.apple.developer.carplay-video'] = true
  delete fixture.profile.Entitlements['com.apple.developer.carplay-audio']
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /CarPlay Audio/)
  fixture.profile.Entitlements['com.apple.developer.carplay-audio'] = true
  assert.doesNotThrow(() => validateProfile(fixture.entitlements, fixture.profile, config))
  delete fixture.entitlements['com.apple.developer.carplay-audio']
  assert.throws(() => validateProfile(fixture.entitlements, fixture.profile, config), /CarPlay Audio/)
  for (const command of ['install', 'archive', 'upload', 'check']) {
    assert.throws(() => argumentsFor([command, '--carplay-video']), /Unknown option/)
  }
})
