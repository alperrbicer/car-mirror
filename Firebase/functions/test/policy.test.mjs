import test from 'node:test'
import assert from 'node:assert/strict'
import { registrationData, validateRegistration, validateMessage, canSend, isPermanentTokenError, retentionMS } from '../policy.mjs'

const active = { revision: 1, enabled: true, token: 'firebase-token-1234567890', locale: 'tr', appVersion: '1.10.0' }

test('registration rejects malformed, oversized and unexpected data', () => {
  for (const input of [null, {}, { ...active, token: 'short' }, { ...active, token: 'x'.repeat(4097) },
    { ...active, revision: -1 }, { ...active, revision: 1.5 }, { ...active, enabled: 'true' },
    { ...active, appVersion: 'invalid' }, { ...active, locale: '../../' }, { ...active, mediaURL: 'https://private.test' },
    { revision: 2, enabled: false, token: active.token }]) assert.throws(() => validateRegistration(input))
  assert.deepEqual(validateRegistration(active), active)
})
test('opt-out removes token and metadata; delayed requests cannot re-enable it', () => {
  const previous = registrationData(null, active, 1000)
  const disabled = registrationData(previous, { revision: 3, enabled: false }, 2000)
  assert.equal(disabled.enabled, false)
  assert.equal(disabled.token, undefined)
  assert.equal(disabled.locale, undefined)
  assert.equal(disabled.appVersion, undefined)
  assert.equal(disabled.expiresAt.getTime(), 2000 + retentionMS)
  assert.equal(registrationData(disabled, { ...active, revision: 2 }), null)
  assert.equal(registrationData(disabled, { ...active, revision: 3 }), null)
})
test('only opted-in, unexpired records can receive notifications', () => {
  const record = registrationData(null, active, 1000)
  assert.equal(canSend(record, 2000), true)
  assert.equal(canSend(record, 1000 + retentionMS), false)
  assert.equal(canSend({ ...record, enabled: false }, 2000), false)
  assert.equal(canSend({ ...record, token: null }, 2000), false)
})
test('payload allows only bounded text and known destinations', () => {
  assert.deepEqual(validateMessage({ title: ' Mirivo ', body: ' Update ', route: 'home' }), { title: 'Mirivo', body: 'Update', route: 'home' })
  for (const changes of [{ route: 'https://example.com' }, { title: '' }, { body: 'x'.repeat(501) }, { url: 'https://example.com' }]) {
    assert.throws(() => validateMessage({ title: 'Mirivo', body: 'Update', route: 'home', ...changes }))
  }
})
test('invalid argument and credential failures never classify a token as invalid', () => {
  assert.equal(isPermanentTokenError('messaging/registration-token-not-registered'), true)
  for (const code of ['messaging/invalid-argument', 'messaging/authentication-error', 'messaging/server-unavailable', undefined]) {
    assert.equal(isPermanentTokenError(code), false)
  }
})
