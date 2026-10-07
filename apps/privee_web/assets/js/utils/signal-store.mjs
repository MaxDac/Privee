/**
 * Operation-scoped implementation of the libsignal `StorageType`.
 *
 * A `SignalStore` instance is created for one logical operation (for example
 * "encrypt a message and queue it in the outbox"). Every mutation performed by
 * the library or by our code is staged in memory; reads see staged writes first.
 * `commit()` then writes everything in a single IndexedDB transaction with
 * synchronous requests, so ratchet state, history and outbox never diverge.
 * A failed operation simply discards the stage.
 */

import { Stores, promisifyRequest, transactionDone } from "./signal-db.mjs"

const DELETED = Symbol("deleted")

/** Stores using an in-line key path: `put(value)` instead of `put(value, key)`. */
const INLINE_KEYS = /** @type {Record<string, string>} */ ({
  [Stores.history]: "id",
  [Stores.pendingOutbox]: "nonce",
})

/** Record field holding the key, used to merge staged writes in `getAll`. */
const RECORD_KEYS = /** @type {Record<string, string>} */ ({
  ...INLINE_KEYS,
  [Stores.signedPrekeys]: "keyId",
})

/** Raised when a peer presents an identity key different from the pinned one. */
export class IdentityChangedError extends Error {
  /**
   * @param {string} peer
   * @param {ArrayBuffer} identityKey
   */
  constructor(peer, identityKey) {
    super(`The identity key of ${peer} changed`)
    this.name = "IdentityChangedError"
    this.peer = peer
    this.identityKey = identityKey
  }
}

/**
 * @param {ArrayBuffer | Uint8Array | undefined | null} a
 * @param {ArrayBuffer | Uint8Array | undefined | null} b
 * @returns {boolean}
 */
export const equalBuffers = (a, b) => {
  if (!a || !b) return false
  const x = a instanceof Uint8Array ? a : new Uint8Array(a)
  const y = b instanceof Uint8Array ? b : new Uint8Array(b)
  if (x.byteLength !== y.byteLength) return false
  for (let i = 0; i < x.byteLength; i++) if (x[i] !== y[i]) return false
  return true
}

/**
 * The library uses both `name` and `name.deviceId` as identity keys: normalize to name.
 * @param {string | number} encodedAddress
 * @returns {string}
 */
export const addressName = (encodedAddress) => String(encodedAddress).replace(/\.\d+$/, "")

/**
 * @typedef {object} TrustRecord
 * @property {ArrayBuffer} publicKey Pinned identity key.
 * @property {ArrayBuffer} [pendingKey] Changed key seen but not yet approved.
 * @property {ArrayBuffer} [approvedKey] Changed key approved by the user.
 */

export class SignalStore {
  /**
   * @param {IDBDatabase} db
   */
  constructor(db) {
    this.db = db
    /** @type {Map<string, Map<IDBValidKey, any>>} */
    this.stage = new Map()
    /** @type {Set<string>} Stores to clear before applying staged writes. */
    this.cleared = new Set()
  }

  // -- Generic staged access ------------------------------------------------

  /**
   * @param {string} store
   * @param {IDBValidKey} key
   * @returns {Promise<any>}
   */
  get(store, key) {
    const staged = this.stage.get(store)
    if (staged?.has(key)) {
      const value = staged.get(key)
      return Promise.resolve(value === DELETED ? undefined : value)
    }
    if (this.cleared.has(store)) return Promise.resolve(undefined)

    const tx = this.db.transaction(store, "readonly")
    return promisifyRequest(tx.objectStore(store).get(key))
  }

  /**
   * Returns the records of a key-path store matching `filter`, with staged
   * writes applied. `index`/`range` narrow the committed read; `filter` must
   * express the same condition so staged records are selected consistently.
   * @param {string} store
   * @param {{index?: string, range?: IDBKeyRange, filter?: (record: any) => boolean}} [options]
   * @returns {Promise<any[]>}
   */
  async getAll(store, { index, range, filter = () => true } = {}) {
    const keyPath = RECORD_KEYS[store]
    if (!keyPath) throw new Error(`getAll is not supported on ${store}`)

    let committed = /** @type {any[]} */ ([])
    if (!this.cleared.has(store)) {
      const tx = this.db.transaction(store, "readonly")
      const source = index ? tx.objectStore(store).index(index) : tx.objectStore(store)
      committed = await promisifyRequest(source.getAll(range))
    }
    const byKey = new Map(committed.filter(filter).map((r) => [r[keyPath], r]))

    for (const [key, value] of this.stage.get(store) || []) {
      if (value === DELETED || !filter(value)) byKey.delete(key)
      else byKey.set(key, value)
    }
    return [...byKey.values()]
  }

  /**
   * @param {string} store
   * @param {IDBValidKey} key
   * @param {any} value
   */
  put(store, key, value) {
    let staged = this.stage.get(store)
    if (!staged) {
      staged = new Map()
      this.stage.set(store, staged)
    }
    staged.set(key, value)
  }

  /**
   * @param {string} store
   * @param {IDBValidKey} key
   */
  delete(store, key) {
    this.put(store, key, DELETED)
  }

  /**
   * Stages the removal of every record of `store`.
   * @param {string} store
   */
  clear(store) {
    this.cleared.add(store)
    this.stage.delete(store)
  }

  /**
   * Writes all staged changes atomically. No `await` happens between the
   * creation of the transaction and the last request.
   * @returns {Promise<void>}
   */
  async commit() {
    const names = [...new Set([...this.cleared, ...this.stage.keys()])]
    if (names.length === 0) return

    const tx = this.db.transaction(names, "readwrite")
    const done = transactionDone(tx)

    try {
      for (const name of this.cleared) tx.objectStore(name).clear()
      for (const [name, entries] of this.stage) {
        const objectStore = tx.objectStore(name)
        const inline = Boolean(INLINE_KEYS[name])
        for (const [key, value] of entries) {
          if (value === DELETED) objectStore.delete(key)
          else if (inline) objectStore.put(value)
          else objectStore.put(value, key)
        }
      }
    } catch (e) {
      tx.abort()
      await done.catch(() => {})
      throw e
    }

    await done
    this.discard()
  }

  /** Discards all staged changes. */
  discard() {
    this.stage.clear()
    this.cleared.clear()
  }

  // -- Identity -------------------------------------------------------------

  getIdentityKeyPair() {
    return this.get(Stores.identity, "keyPair")
  }

  getLocalRegistrationId() {
    return this.get(Stores.identity, "registrationId")
  }

  /**
   * Never waits on the UI: unknown peers are trusted on first use, changed keys
   * only once approved.
   * @param {string} identifier
   * @param {ArrayBuffer} identityKey
   * @returns {Promise<boolean>}
   */
  async isTrustedIdentity(identifier, identityKey) {
    /** @type {TrustRecord | undefined} */
    const record = await this.get(Stores.trustedIdentities, addressName(identifier))
    if (!record) return true
    return (
      equalBuffers(record.publicKey, identityKey) || equalBuffers(record.approvedKey, identityKey)
    )
  }

  /**
   * Pins the identity of a peer. Refuses (throws) to replace a pinned key that
   * was not approved: the library does not always await `isTrustedIdentity`.
   * @param {string} encodedAddress
   * @param {ArrayBuffer} identityKey
   * @returns {Promise<boolean>} Whether a previous key was replaced.
   */
  async saveIdentity(encodedAddress, identityKey) {
    const name = addressName(encodedAddress)
    /** @type {TrustRecord | undefined} */
    const record = await this.get(Stores.trustedIdentities, name)

    if (!record) {
      this.put(Stores.trustedIdentities, name, { publicKey: identityKey })
      return false
    }

    if (equalBuffers(record.publicKey, identityKey)) return false

    if (equalBuffers(record.approvedKey, identityKey)) {
      this.put(Stores.trustedIdentities, name, { publicKey: identityKey })
      return true
    }

    throw new IdentityChangedError(name, identityKey)
  }

  /**
   * @param {string} name
   * @returns {Promise<TrustRecord | undefined>}
   */
  getTrust(name) {
    return this.get(Stores.trustedIdentities, addressName(name))
  }

  // -- Prekeys --------------------------------------------------------------

  /**
   * @param {string | number} keyId
   */
  loadPreKey(keyId) {
    const id = Number(keyId)
    if (!id) return Promise.resolve(undefined)
    return this.get(Stores.prekeys, id)
  }

  /**
   * @param {string | number} keyId
   * @param {import("@privacyresearch/libsignal-protocol-typescript").KeyPairType} keyPair
   */
  storePreKey(keyId, keyPair) {
    this.put(Stores.prekeys, Number(keyId), keyPair)
    return Promise.resolve()
  }

  /**
   * @param {string | number} keyId
   */
  removePreKey(keyId) {
    this.delete(Stores.prekeys, Number(keyId))
    return Promise.resolve()
  }

  /**
   * @param {string | number} keyId
   */
  async loadSignedPreKey(keyId) {
    const record = await this.get(Stores.signedPrekeys, Number(keyId))
    return record?.keyPair
  }

  /**
   * @param {string | number} keyId
   * @param {import("@privacyresearch/libsignal-protocol-typescript").KeyPairType} keyPair
   */
  async storeSignedPreKey(keyId, keyPair) {
    const id = Number(keyId)
    const existing = await this.get(Stores.signedPrekeys, id)
    this.put(Stores.signedPrekeys, id, { createdAt: Date.now(), ...existing, keyId: id, keyPair })
  }

  /**
   * @param {string | number} keyId
   */
  removeSignedPreKey(keyId) {
    this.delete(Stores.signedPrekeys, Number(keyId))
    return Promise.resolve()
  }

  // -- Sessions -------------------------------------------------------------

  /**
   * @param {string} encodedAddress
   * @param {string} record
   */
  storeSession(encodedAddress, record) {
    this.put(Stores.sessions, encodedAddress, record)
    return Promise.resolve()
  }

  /**
   * @param {string} encodedAddress
   * @returns {Promise<string | undefined>}
   */
  loadSession(encodedAddress) {
    return this.get(Stores.sessions, encodedAddress)
  }

  /**
   * @param {string} encodedAddress
   */
  removeSession(encodedAddress) {
    this.delete(Stores.sessions, encodedAddress)
    return Promise.resolve()
  }
}
