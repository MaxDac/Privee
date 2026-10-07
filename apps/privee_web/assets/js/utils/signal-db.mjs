/**
 * IndexedDB database holding the Signal Protocol state of one Privee session.
 *
 * Every own session gets its own database (`privee-<ownSessionId>`), so several
 * sessions used in the same browser never share or overwrite key material.
 */

/**
 * Version 2: libsignal (PQXDH) replaced libsignal-protocol-typescript. Key material,
 * pinned identities and protocol metadata of version 1 are incompatible and dropped;
 * the local history and the pending outbox (re-encrypted on flush) are kept.
 */
export const DB_VERSION = 2

export const LEGACY_DB_NAME = "SignalKeyStore"

/** Object stores. All use out-of-line keys unless a key path is given. */
export const Stores = Object.freeze({
  /** Serialized libsignal state (protocol) and the own public identity key. */
  identity: "identity",
  /** Lifecycle of signed (and Kyber last-resort) prekeys: {keyId, createdAt, retiredAt?}. */
  signedPrekeys: "signed_prekeys",
  trustedIdentities: "trusted_identities",
  meta: "meta",
  history: "history",
  pendingOutbox: "pending_outbox",
})

export const ALL_STORES = Object.values(Stores)

/**
 * @param {string | number} ownSessionId
 * @returns {string}
 */
export const dbNameFor = (ownSessionId) => `privee-${ownSessionId}`

/**
 * Wraps an IDBRequest into a promise.
 * @template T
 * @param {IDBRequest<T>} request
 * @returns {Promise<T>}
 */
export const promisifyRequest = (request) =>
  new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })

/**
 * Resolves when the transaction commits, rejects when it aborts or fails.
 * @param {IDBTransaction} tx
 * @returns {Promise<void>}
 */
export const transactionDone = (tx) =>
  new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error || new Error("Transaction aborted"))
  })

/** Stores of version 1 holding key material of the previous library. */
const LEGACY_STORES = ["prekeys", "sessions"]

/**
 * @param {IDBDatabase} db
 * @param {IDBTransaction} tx Version change transaction.
 * @param {number} oldVersion
 */
const upgrade = (db, tx, oldVersion) => {
  for (const name of LEGACY_STORES) {
    if (db.objectStoreNames.contains(name)) db.deleteObjectStore(name)
  }

  for (const name of [
    Stores.identity,
    Stores.signedPrekeys,
    Stores.trustedIdentities,
    Stores.meta,
  ]) {
    if (!db.objectStoreNames.contains(name)) db.createObjectStore(name)
    else if (oldVersion < 2) tx.objectStore(name).clear()
  }

  if (!db.objectStoreNames.contains(Stores.history)) {
    const history = db.createObjectStore(Stores.history, { keyPath: "id" })
    history.createIndex("peer_ts", ["peerId", "ts"])
  }

  if (!db.objectStoreNames.contains(Stores.pendingOutbox)) {
    const outbox = db.createObjectStore(Stores.pendingOutbox, { keyPath: "nonce" })
    outbox.createIndex("peer", "peerId")
  }
}

/**
 * Opens (creating or upgrading) the database of `ownSessionId`. The connection
 * closes itself when another tab needs a version upgrade.
 * @param {string | number} ownSessionId
 * @param {IDBFactory} [factory]
 * @returns {Promise<IDBDatabase>}
 */
export const openSignalDb = (ownSessionId, factory = globalThis.indexedDB) =>
  new Promise((resolve, reject) => {
    if (!factory) {
      reject(new Error("IndexedDB is not available"))
      return
    }

    const request = factory.open(dbNameFor(ownSessionId), DB_VERSION)
    request.onupgradeneeded = (event) =>
      upgrade(request.result, /** @type {IDBTransaction} */ (request.transaction), event.oldVersion)
    request.onerror = () => reject(request.error)
    request.onblocked = () => reject(new Error("Database upgrade blocked by another tab"))
    request.onsuccess = () => {
      const db = request.result
      db.onversionchange = () => db.close()
      resolve(db)
    }
  })

/**
 * Deletes a database by name.
 * @param {string} name
 * @param {IDBFactory} [factory]
 * @returns {Promise<void>}
 */
const deleteDb = (name, factory = globalThis.indexedDB) =>
  new Promise((resolve, reject) => {
    if (!factory) {
      resolve()
      return
    }

    const request = factory.deleteDatabase(name)
    request.onsuccess = () => resolve()
    request.onerror = () => reject(request.error)
    // Other connections receive `versionchange` and close; deletion then proceeds.
    request.onblocked = () => {}
  })

/**
 * Deletes all Signal state and local history of `ownSessionId` on this device.
 * @param {string | number} ownSessionId
 * @param {IDBFactory} [factory]
 * @returns {Promise<void>}
 */
export const deleteSignalDb = (ownSessionId, factory) => deleteDb(dbNameFor(ownSessionId), factory)

/**
 * Deletes the database of the legacy hand-rolled implementation.
 * @param {IDBFactory} [factory]
 * @returns {Promise<void>}
 */
export const deleteLegacyDb = (factory) => deleteDb(LEGACY_DB_NAME, factory)
