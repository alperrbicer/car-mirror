import { createHash } from 'node:crypto'

export const retentionMS = 180 * 24 * 60 * 60 * 1000
export const routes = new Set(['home', 'library', 'settings'])
export const tokenHash = token => createHash('sha256').update(token).digest('hex')

export function validateRegistration(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      !Number.isSafeInteger(input.revision) || input.revision < 1 || typeof input.enabled !== 'boolean') {
    throw new Error('Invalid registration')
  }
  const allowed = input.enabled ? ['revision', 'enabled', 'token', 'locale', 'appVersion'] : ['revision', 'enabled']
  if (Object.keys(input).some(key => !allowed.includes(key))) throw new Error('Unexpected registration field')
  if (input.enabled && (
    typeof input.token !== 'string' || input.token.length < 20 || input.token.length > 4096 || /\s/.test(input.token) ||
    typeof input.locale !== 'string' || !/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$/.test(input.locale) ||
    typeof input.appVersion !== 'string' || !/^\d{1,9}(?:\.\d{1,9}){0,2}$/.test(input.appVersion)
  )) throw new Error('Invalid token metadata')
  return input
}

export function registrationData(previous, input, now = Date.now()) {
  validateRegistration(input)
  if (previous && input.revision <= previous.revision) return null
  const common = { enabled: input.enabled, revision: input.revision, updatedAt: new Date(now), expiresAt: new Date(now + retentionMS) }
  // Full replacement drops token, locale and version on opt-out.
  return input.enabled ? { ...common, token: input.token, locale: input.locale, appVersion: input.appVersion } : common
}

export function validateMessage(input) {
  if (!input || Object.keys(input).some(key => !['title', 'body', 'route'].includes(key)) ||
      typeof input.title !== 'string' || !input.title.trim() || input.title.length > 100 ||
      typeof input.body !== 'string' || !input.body.trim() || input.body.length > 500 || !routes.has(input.route)) {
    throw new Error('Message needs title (1-100), body (1-500), and route: home, library or settings')
  }
  return { title: input.title.trim(), body: input.body.trim(), route: input.route }
}

export function isPermanentTokenError(code) {
  return ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)
}

export function canSend(record, now = Date.now()) {
  const expiry = record?.expiresAt?.toDate?.() ?? record?.expiresAt
  return record?.enabled === true && typeof record.token === 'string' && expiry instanceof Date && expiry.getTime() > now
}
