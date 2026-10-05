import { registrationData, tokenHash } from './policy.mjs'

export async function synchronizeInstallation(db, uid, input) {
  const ref = db.collection('notificationInstallations').doc(uid)
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref)
    const previous = snapshot.data()
    const next = registrationData(previous, input)
    if (!next) return { applied: false, revision: previous.revision }
    const ownerRef = next.token ? db.collection('notificationTokenOwners').doc(tokenHash(next.token)) : null
    if (ownerRef) {
      const owner = (await transaction.get(ownerRef)).data()
      if (owner && owner.uid !== uid && owner.expiresAt.toMillis() > Date.now()) {
        const error = new Error('Token belongs to another installation')
        error.code = 'already-exists'
        throw error
      }
    }
    const oldOwnerRef = previous?.token && previous.token !== next.token
      ? db.collection('notificationTokenOwners').doc(tokenHash(previous.token)) : null
    const oldOwner = oldOwnerRef ? (await transaction.get(oldOwnerRef)).data() : null
    // All reads precede writes, as required by Firestore transactions.
    if (oldOwner?.uid === uid) transaction.delete(oldOwnerRef)
    if (ownerRef) transaction.set(ownerRef, { uid, expiresAt: next.expiresAt })
    transaction.set(ref, next)
    return { applied: true }
  })
}

export async function removeInvalidToken(db, uid, sentToken) {
  const ref = db.collection('notificationInstallations').doc(uid)
  await db.runTransaction(async transaction => {
    const record = (await transaction.get(ref)).data()
    // An old send failure must not delete a freshly rotated token.
    if (record?.token !== sentToken) return
    const ownerRef = db.collection('notificationTokenOwners').doc(tokenHash(sentToken))
    const owner = (await transaction.get(ownerRef)).data()
    const { token, locale, appVersion, ...rest } = record
    transaction.set(ref, { ...rest, enabled: false })
    if (owner?.uid === uid) transaction.delete(ownerRef)
  })
}
