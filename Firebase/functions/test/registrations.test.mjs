import test from 'node:test'
import assert from 'node:assert/strict'
import { initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { synchronizeInstallation, removeInvalidToken } from '../registrations.mjs'
import { sendToInstallation } from '../sender.mjs'
import { tokenHash } from '../policy.mjs'

// Run against Firestore's actual transaction engine and deployed local rules.
const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST)
const db = emulator ? getFirestore(initializeApp({ projectId: 'demo-mirivo' })) : null
const active = { revision: 1, enabled: true, token: 'firebase-token-1234567890', locale: 'tr', appVersion: '1.0' }
const message = { title: 'Mirivo', body: 'Update', route: 'home' }

test('Firestore registration, rotation, opt-out and sender behavior', { skip: !emulator }, async t => {
  await db.recursiveDelete(db.collection('notificationInstallations'))
  await db.recursiveDelete(db.collection('notificationTokenOwners'))
  await synchronizeInstallation(db, 'user-one', active)
  await t.test('another user cannot claim an existing token', async () => {
    await assert.rejects(synchronizeInstallation(db, 'user-two', active), /belongs/)
  })
  await t.test('dry-run never calls FCM', async () => {
    const result = await sendToInstallation({ db, uid: 'user-one', message, messaging: { send() { throw new Error('must not send') } } })
    assert.equal(result, 'eligible')
  })
  const rotated = { ...active, token: 'rotated-firebase-token-123456', revision: 2 }
  await t.test('rotation deletes the old index; old failures cannot delete the new token', async () => {
    await synchronizeInstallation(db, 'user-one', rotated)
    await removeInvalidToken(db, 'user-one', active.token)
    assert.equal((await db.doc('notificationInstallations/user-one').get()).data().token, rotated.token)
    assert.equal((await db.doc(`notificationTokenOwners/${tokenHash(active.token)}`).get()).exists, false)
  })
  await t.test('FCM acceptance is reported separately from device delivery', async () => {
    const result = await sendToInstallation({ db, uid: 'user-one', message, dryRun: false, messaging: { async send(payload) {
      assert.equal(payload.token, rotated.token); assert.equal(payload.data.route, 'home'); return 'message-id'
    } } })
    assert.equal(result, 'accepted')
  })
  await t.test('generic send failures retain the registration', async () => {
    const result = await sendToInstallation({ db, uid: 'user-one', message, dryRun: false, messaging: { async send() {
      throw Object.assign(new Error(), { code: 'messaging/invalid-argument' })
    } } })
    assert.equal(result, 'failed')
    assert.equal((await db.doc('notificationInstallations/user-one').get()).data().token, rotated.token)
  })
  await t.test('permanent errors erase the token and its index', async () => {
    const result = await sendToInstallation({ db, uid: 'user-one', message, dryRun: false, messaging: { async send() {
      throw Object.assign(new Error(), { code: 'messaging/registration-token-not-registered' })
    } } })
    assert.equal(result, 'removed')
    assert.equal((await db.doc('notificationInstallations/user-one').get()).data().token, undefined)
  })
  await t.test('simultaneous updates converge to the highest revision and disabled tokens are not sent', async () => {
    await Promise.all([synchronizeInstallation(db, 'user-one', { ...rotated, revision: 3 }),
      synchronizeInstallation(db, 'user-one', { enabled: false, revision: 4 })])
    const stored = (await db.doc('notificationInstallations/user-one').get()).data()
    assert.equal(stored.enabled, false); assert.equal(stored.token, undefined); assert.equal(stored.revision, 4)
    assert.equal(await sendToInstallation({ db, uid: 'user-one', message, dryRun: false,
      messaging: { send() { throw new Error('must not send') } } }), 'skipped')
  })
  await t.test('Firestore rules deny direct unauthenticated token access', async () => {
    const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-mirivo/databases/(default)/documents/notificationInstallations/user-one`
    assert.equal((await fetch(url)).status, 403)
  })
  await db.terminate()
})
