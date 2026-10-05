import { initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { onCall, HttpsError } from 'firebase-functions/v2/https'
import { defineString } from 'firebase-functions/params'
import { validateRegistration } from './policy.mjs'
import { synchronizeInstallation } from './registrations.mjs'

initializeApp()
const region = defineString('FUNCTIONS_REGION', { default: 'europe-west1' })
const iosAppID = defineString('IOS_FIREBASE_APP_ID', { description: 'GOOGLE_APP_ID from the Mirivo GoogleService-Info.plist' })

export const syncNotificationInstallation = onCall({
  region, enforceAppCheck: true, maxInstances: 5, timeoutSeconds: 30,
}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required')
  if (request.app?.appId !== iosAppID.value()) throw new HttpsError('permission-denied', 'Unexpected app')
  try { validateRegistration(request.data) }
  catch { throw new HttpsError('invalid-argument', 'Invalid notification registration') }
  try { return await synchronizeInstallation(getFirestore(), request.auth.uid, request.data) }
  catch (error) {
    if (error.code === 'already-exists') throw new HttpsError('already-exists', 'Token belongs to another installation')
    // Never log tokens, UID, payloads or authorization headers.
    throw new HttpsError('internal', 'Registration could not be saved')
  }
})
