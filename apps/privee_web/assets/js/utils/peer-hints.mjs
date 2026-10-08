/**
 * Local conversation metadata: the peer session name, an optional "hint"
 * about who is speaking, and the list of conversations held on this browser.
 *
 * Everything lives in the peer metadata (`meta` store, key `peer:<id>`) of the
 * own session's database and never leaves the browser: hints are not sent to
 * the server, used in notifications or logged. They survive "Clear history on
 * this device" and are deleted on sign-out and on "Forget this device".
 *
 * Writes must hold the keys lock exclusively, like every other writer of the
 * peer metadata, so a concurrent ratchet step cannot overwrite them.
 */

import { Stores, dbNameFor, openSignalDb, promisifyRequest } from "./signal-db.mjs"
import { webLocks } from "./signal-locks.mjs"

export const HINT_MAX_LENGTH = 40

const PEER_PREFIX = "peer:"
const SIGN_OUT_LOCK_TIMEOUT_MS = 3000

/**
 * @typedef {object} Conversation
 * @property {number} peerId
 * @property {string} name Peer session name.
 * @property {string | null} hint
 * @property {number | null} lastMessageAt Timestamp of the last local message.
 * @property {number} lastActivity Last message or last time the chat was opened.
 */

/** @param {number | string} peerId */
export const peerMetaKey = (peerId) => `${PEER_PREFIX}${peerId}`

/** @param {number | string} ownId */
export const keysLockName = (ownId) => `privee-keys-${ownId}`

/**
 * Normalizes a hint: a single trimmed line of at most `HINT_MAX_LENGTH`
 * characters, without control or bidirectional override characters.
 * @param {unknown} value
 * @returns {string | null} `null` when blank (the hint is removed).
 */
export const normalizeHint = (value) => {
  const text = String(value ?? "")
    .replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
    .replace(/\s+/g, " ")
    .replace(/\p{Cc}/gu, "")
    .trim()
  if (!text) return null
  return Array.from(text).slice(0, HINT_MAX_LENGTH).join("").trim()
}

/**
 * Applies `update` to the metadata of `peerId` in one read-write transaction.
 * @param {IDBDatabase} db
 * @param {number | string} peerId
 * @param {(meta: Record<string, any>) => Record<string, any>} update
 * @returns {Promise<Record<string, any>>}
 */
export const updatePeerMeta = (db, peerId, update) =>
  new Promise((resolve, reject) => {
    const tx = db.transaction(Stores.meta, "readwrite")
    const store = tx.objectStore(Stores.meta)
    const key = peerMetaKey(peerId)
    /** @type {Record<string, any>} */
    let next = {}
    const request = store.get(key)
    request.onsuccess = () => {
      next = update({ ...(request.result || {}) })
      store.put(next, key)
    }
    tx.oncomplete = () => resolve(next)
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("Transaction aborted"))
  })

/**
 * @param {IDBDatabase} db
 * @param {number | string} peerId
 * @returns {Promise<string | null>}
 */
export const readPeerHint = async (db, peerId) => {
  const tx = db.transaction(Stores.meta, "readonly")
  const meta = await promisifyRequest(tx.objectStore(Stores.meta).get(peerMetaKey(peerId)))
  return typeof meta?.hint === "string" ? meta.hint : null
}

/**
 * Stores the peer session name, so the conversation appears in the local list.
 * @param {IDBDatabase} db
 * @param {number | string} peerId
 * @param {string} name
 * @param {number} now
 */
export const writePeerName = (db, peerId, name, now) =>
  updatePeerMeta(db, peerId, (meta) => ({ ...meta, name, openedAt: now }))

/**
 * Stores (or, when blank, removes) the hint of `peerId`.
 * @param {IDBDatabase} db
 * @param {number | string} peerId
 * @param {unknown} hint
 * @returns {Promise<string | null>} The stored hint.
 */
export const writePeerHint = async (db, peerId, hint) => {
  const value = normalizeHint(hint)
  await updatePeerMeta(db, peerId, (meta) => {
    delete meta.hint
    return value ? { ...meta, hint: value } : meta
  })
  return value
}

/**
 * Removes every hint of the session, keeping the rest of the peer metadata.
 * @param {IDBDatabase} db
 * @returns {Promise<void>}
 */
export const removePeerHints = (db) =>
  new Promise((resolve, reject) => {
    const tx = db.transaction(Stores.meta, "readwrite")
    const request = tx.objectStore(Stores.meta).openCursor()
    request.onsuccess = () => {
      const cursor = request.result
      if (!cursor) return
      const value = cursor.value
      if (
        typeof cursor.key === "string" &&
        cursor.key.startsWith(PEER_PREFIX) &&
        value &&
        typeof value === "object" &&
        "hint" in value
      ) {
        const rest = { ...value }
        delete rest.hint
        cursor.update(rest)
      }
      cursor.continue()
    }
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("Transaction aborted"))
  })

/**
 * Lists the conversations of this session on this browser whose peer name is
 * known, most recent first.
 * @param {IDBDatabase} db
 * @returns {Promise<Conversation[]>}
 */
export const listConversations = (db) =>
  new Promise((resolve, reject) => {
    const tx = db.transaction([Stores.meta, Stores.history], "readonly")
    /** @type {Conversation[]} */
    const conversations = []

    const metaRequest = tx.objectStore(Stores.meta).openCursor()
    metaRequest.onsuccess = () => {
      const cursor = metaRequest.result
      if (!cursor) return
      const key = cursor.key
      const meta = cursor.value
      if (
        typeof key === "string" &&
        key.startsWith(PEER_PREFIX) &&
        typeof meta?.name === "string"
      ) {
        const conversation = {
          peerId: Number(key.slice(PEER_PREFIX.length)),
          name: meta.name,
          hint: typeof meta.hint === "string" ? meta.hint : null,
          lastMessageAt: /** @type {number | null} */ (null),
          lastActivity: Number(meta.openedAt) || 0,
        }
        conversations.push(conversation)

        const id = conversation.peerId
        const last = tx
          .objectStore(Stores.history)
          .index("peer_ts")
          .openCursor(IDBKeyRange.bound([id, -Infinity], [id, Infinity]), "prev")
        last.onsuccess = () => {
          const ts = last.result?.value?.ts
          if (typeof ts === "number") {
            conversation.lastMessageAt = ts
            conversation.lastActivity = Math.max(conversation.lastActivity, ts)
          }
        }
      }
      cursor.continue()
    }

    tx.oncomplete = () =>
      resolve(
        conversations.sort(
          (a, b) => b.lastActivity - a.lastActivity || a.name.localeCompare(b.name),
        ),
      )
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("Transaction aborted"))
  })

/**
 * Deletes the hints of `ownId` on this browser, before signing out. Does not
 * create the database when it does not exist.
 * @param {number | string} ownId
 * @param {{factory?: IDBFactory, locks?: import("./signal-locks.mjs").Locks | null, timeoutMs?: number}} [options]
 * @returns {Promise<void>}
 */
export const clearHintsOnSignOut = async (ownId, options = {}) => {
  const factory = options.factory ?? globalThis.indexedDB
  if (!factory) return

  if (typeof factory.databases === "function") {
    const names = (await factory.databases()).map((db) => db.name)
    if (!names.includes(dbNameFor(ownId))) return
  }

  let locks = options.locks
  if (locks === undefined) {
    try {
      locks = webLocks()
    } catch {
      locks = null
    }
  }

  const db = await openSignalDb(ownId, factory)
  /** @type {Promise<void> | null} */
  let clearing = null
  const clear = () => {
    if (!clearing) clearing = removePeerHints(db)
    return clearing
  }

  try {
    if (!locks) return await clear()

    // Sign-out must not hang behind a long key operation of another tab.
    /** @type {ReturnType<typeof setTimeout> | undefined} */
    let timer
    const timeout = new Promise((resolve) => {
      timer = setTimeout(resolve, options.timeoutMs ?? SIGN_OUT_LOCK_TIMEOUT_MS)
    })
    await Promise.race([
      locks.request(keysLockName(ownId), { mode: "exclusive" }, clear).catch(() => {}),
      timeout,
    ])
    clearTimeout(timer)
    await clear()
  } finally {
    db.close()
  }
}
