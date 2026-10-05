#!/usr/bin/env node
import { readFile } from 'node:fs/promises'
import { parseArgs } from 'node:util'
import { initializeApp, applicationDefault } from 'firebase-admin/app'
import { getFirestore, FieldPath } from 'firebase-admin/firestore'
import { getMessaging } from 'firebase-admin/messaging'
import { validateMessage } from './policy.mjs'
import { sendToInstallation } from './sender.mjs'

const { values } = parseArgs({ options: {
  project: { type: 'string' }, file: { type: 'string' }, uid: { type: 'string' },
  all: { type: 'boolean', default: false }, send: { type: 'boolean', default: false },
} })
if (!values.project || !values.file || Boolean(values.uid) === values.all) {
  throw new Error('Usage: node send.mjs --project PROJECT_ID --file message.json (--uid UID | --all) [--send]. Defaults to dry-run.')
}
const message = validateMessage(JSON.parse(await readFile(values.file, 'utf8')))
initializeApp({ credential: applicationDefault(), projectId: values.project })
const db = getFirestore(), messaging = getMessaging()
const counts = { eligible: 0, accepted: 0, removed: 0, skipped: 0, failed: 0 }
async function send(uid) { counts[await sendToInstallation({ db, messaging, uid, message, dryRun: !values.send })]++ }
if (values.uid) await send(values.uid)
else {
  let cursor
  while (true) {
    let query = db.collection('notificationInstallations').where('enabled', '==', true).orderBy(FieldPath.documentId()).limit(200)
    if (cursor) query = query.startAfter(cursor)
    const page = await query.get()
    // Bounded concurrency and no automatic retry of accepted notifications.
    for (let offset = 0; offset < page.docs.length; offset += 10) await Promise.all(page.docs.slice(offset, offset + 10).map(doc => send(doc.id)))
    if (page.size < 200) break
    cursor = page.docs.at(-1)
  }
}
console.log(JSON.stringify({ mode: values.send ? 'send' : 'dry-run', ...counts, note: 'accepted means FCM accepted the request, not device delivery' }))
if (counts.failed) process.exitCode = 1
