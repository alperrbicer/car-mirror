import test from 'node:test'
import assert from 'node:assert/strict'

process.env.IOS_FIREBASE_APP_ID = 'test-ios-app'
const { syncNotificationInstallation } = await import('../index.mjs')

test('callable rejects anonymous HTTP callers without Firebase Auth', async () => {
  await assert.rejects(syncNotificationInstallation.run({ data: {}, app: { appId: 'test-ios-app' } }), { code: 'unauthenticated' })
})
test('callable rejects missing or mismatched App Check application identity', async () => {
  for (const app of [undefined, { appId: 'another-project-app' }]) {
    await assert.rejects(syncNotificationInstallation.run({ data: {}, auth: { uid: 'user-one' }, app }), { code: 'permission-denied' })
  }
})
test('callable validates payload before any database operation', async () => {
  await assert.rejects(syncNotificationInstallation.run({ data: { token: 'invalid' }, auth: { uid: 'user-one' }, app: { appId: 'test-ios-app' } }), { code: 'invalid-argument' })
})
