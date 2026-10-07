/**
 * Operation-scoped, staged access to the IndexedDB of a Privee session.
 *
 * A `SignalStore` instance is created for one logical operation (for example
 * "encrypt a message and queue it in the outbox"). The libsignal state is a
 * single serialized snapshot (`loadProtocol`/`saveProtocol`); every mutation
 * is staged in memory and reads see staged writes first.
 * `commit()` then writes everything in a single IndexedDB transaction with
 * synchronous requests, so ratchet state, history and outbox never diverge.
 * A failed operation simply discards the stage.
 */

import { Stores, promisifyRequest, transactionDone } from "./signal-db.mjs"
import { Protocol } from "./signal-wasm.mjs"

const PROTOCOL_KEY = "protocol"
const PUBLIC_KEY = "public_key"

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
   * @param {Uint8Array} identityKey
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
 * @typedef {object} TrustRecord
 * @property {Uint8Array} publicKey Pinned identity key.
 * @property {Uint8Array} [pendingKey] Changed key seen but not yet approved.
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

  // -- Protocol state -------------------------------------------------------

  /**
   * Restores the libsignal state. The caller must free() the returned object.
   * @returns {Promise<Protocol | undefined>}
   */
  async loadProtocol() {
    /** @type {Uint8Array | undefined} */
    const bytes = await this.get(Stores.identity, PROTOCOL_KEY)
    return bytes ? Protocol.restore(bytes) : undefined
  }

  /**
   * Stages the libsignal state and the own public identity key.
   * @param {Protocol} protocol
   */
  saveProtocol(protocol) {
    this.put(Stores.identity, PROTOCOL_KEY, protocol.serialize())
    this.put(Stores.identity, PUBLIC_KEY, protocol.identityKey())
  }

  /** @returns {Promise<Uint8Array | undefined>} */
  publicIdentityKey() {
    return this.get(Stores.identity, PUBLIC_KEY)
  }

  // -- Trust ----------------------------------------------------------------

  /**
   * The user-facing trust decision. Unknown peers are trusted on first use,
   * changed keys only once approved.
   * @param {string} name
   * @param {Uint8Array} identityKey
   * @returns {Promise<boolean>}
   */
  async isTrustedIdentity(name, identityKey) {
    /** @type {TrustRecord | undefined} */
    const record = await this.getTrust(name)
    return !record || equalBuffers(record.publicKey, identityKey)
  }

  /**
   * Pins the identity of a peer seen for the first time.
   * @param {string} name
   * @param {Uint8Array} identityKey
   */
  async pinIdentity(name, identityKey) {
    if (!(await this.getTrust(name)))
      this.put(Stores.trustedIdentities, name, { publicKey: identityKey })
  }

  /**
   * @param {string} name
   * @returns {Promise<TrustRecord | undefined>}
   */
  getTrust(name) {
    return this.get(Stores.trustedIdentities, name)
  }
}
