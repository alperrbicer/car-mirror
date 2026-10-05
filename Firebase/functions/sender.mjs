import { canSend, isPermanentTokenError, validateMessage } from './policy.mjs'
import { removeInvalidToken } from './registrations.mjs'

export async function sendToInstallation({ db, messaging, uid, message, dryRun = true }) {
  message = validateMessage(message)
  // Read immediately before sending, so a previously fetched audience cannot bypass opt-out.
  const record = (await db.collection('notificationInstallations').doc(uid).get()).data()
  if (!canSend(record)) return 'skipped'
  if (dryRun) return 'eligible'
  try {
    await messaging.send({ token: record.token,
      notification: { title: message.title, body: message.body }, data: { route: message.route },
      apns: { headers: { 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600) },
        payload: { aps: { sound: 'default' } } },
    })
    return 'accepted'
  } catch (error) {
    if (isPermanentTokenError(error.code)) { await removeInvalidToken(db, uid, record.token); return 'removed' }
    // Bad credentials, malformed payloads, quota and transient errors never delete a token.
    return 'failed'
  }
}
