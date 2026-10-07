/**
 * Signal Protocol client of one Privee session on this device.
 *
 * Wraps `@privacyresearch/libsignal-protocol-typescript` with:
 *   - per-session persistence (`signal-db.mjs`) and atomic, staged operations
 *     (`signal-store.mjs`);
 *   - cross-tab locking (`signal-locks.mjs`): key management takes the
 *     `keys` lock exclusively, peer operations take it shared plus a per-peer lock;
 *   - key publication through the LiveView (`PriveeWeb.SignalKeysLive`);
 *   - conversation epochs: a Signal session is bound to the server epoch it
 *     was built for and rebuilt when the conversation expires;
 *   - a local plaintext history and a pending outbox keyed by client nonce.
 */

import {
  FingerprintGenerator,
  KeyHelper,
  SessionBuilder,
  SessionCipher,
  SignalProtocolAddress,
} from "@privacyresearch/libsignal-protocol-typescript"
import { Stores, deleteLegacyDb, deleteSignalDb, openSignalDb } from "./signal-db.mjs"
import { webLocks } from "./signal-locks.mjs"
import { IdentityChangedError, SignalStore, equalBuffers } from "./signal-store.mjs"

export { IdentityChangedError }

const DEVICE_ID = 1
const DAY_MS = 24 * 60 * 60 * 1000

export const OPK_TARGET = 50
export const OPK_LOW_WATERMARK = 20
export const SPK_ROTATION_MS = 7 * DAY_MS
const DEFAULT_MAX_AGE_MS = 7 * DAY_MS
const MAX_SEND_ATTEMPTS = 4

/** @typedef {"ready" | "needs_reset" | "superseded" | "resetting"} DeviceState */

/**
 * @typedef {object} OutboxRow
 * @property {string} nonce Client nonce, idempotency key on the server.
 * @property {number} peerId
 * @property {1 | 3} type Signal message type.
 * @property {string} body Base64 ciphertext.
 * @property {string} epoch Conversation epoch the session was built for.
 * @property {string} identityKey Own identity key used to encrypt.
 * @property {string} plaintext
 * @property {number} ts
 */

/**
 * @typedef {object} HistoryRow
 * @property {string} id Server message id.
 * @property {number} peerId
 * @property {string} epoch
 * @property {number} seq
 * @property {"in" | "out"} direction
 * @property {string | null} plaintext `null` when the message could not be decrypted.
 * @property {number} ts
 */

/**
 * @typedef {object} ServerMessage
 * @property {string} id
 * @property {number} seq
 * @property {string} epoch
 * @property {number} type
 * @property {string} body
 * @property {"in" | "out"} direction
 * @property {string | null} [client_nonce]
 */

/** @typedef {(event: string, payload: object) => Promise<any>} Push */

export class ServerError extends Error {
  /** @param {string} reason */
  constructor(reason) {
    super(`Server error: ${reason}`)
    this.name = "ServerError"
    this.reason = reason
  }
}

export class NoPeerKeysError extends Error {
  constructor() {
    super("The peer has not published encryption keys yet")
    this.name = "NoPeerKeysError"
  }
}

export class DeviceNotReadyError extends Error {
  /** @param {string | undefined} state */
  constructor(state) {
    super(`This device cannot send messages (${state || "not initialized"})`)
    this.name = "DeviceNotReadyError"
    this.state = state
  }
}

/** Errors thrown by `send` after the message was stored in the outbox. */
const queuedErrors = new WeakSet()

/** @param {unknown} error */
const markQueued = (error) => {
  if (error && typeof error === "object") queuedErrors.add(error)
}

/**
 * Whether `send` failed after queuing the message, which is then delivered by a
 * later `flushOutbox` and must not be sent again.
 * @param {unknown} error
 */
export const wasQueued = (error) => !!error && typeof error === "object" && queuedErrors.has(error)

// -- Encoding helpers ---------------------------------------------------------

/**
 * @param {ArrayBuffer | Uint8Array} buffer
 * @returns {string}
 */
export const bufferToBase64 = (buffer) => {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

/**
 * @param {string} base64
 * @returns {ArrayBuffer}
 */
export const base64ToBuffer = (base64) => {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

const encoder = new TextEncoder()
const decoder = new TextDecoder()

/**
 * @param {string} text
 * @returns {ArrayBuffer}
 */
const utf8 = (text) => {
  const bytes = encoder.encode(text)
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
}

/** @param {number} ms */
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/** @param {number | string} peerId */
const peerMetaKey = (peerId) => `peer:${peerId}`

/** @param {number | string} peerId */
const addressOf = (peerId) => new SignalProtocolAddress(String(peerId), DEVICE_ID)

export class SignalClient {
  /**
   * @param {object} options
   * @param {number | string} options.ownId Own session id.
   * @param {IDBDatabase} options.db
   * @param {Push} options.push Reply-based LiveView push.
   * @param {import("./signal-locks.mjs").Locks} options.locks
   * @param {() => number} [options.now]
   * @param {IDBFactory} [options.factory]
   */
  constructor({ ownId, db, push, locks, now = Date.now, factory }) {
    this.ownId = Number(ownId)
    this.db = db
    this.push = push
    this.locks = locks
    this.now = now
    this.factory = factory
  }

  /**
   * Opens the client of `ownId`. Throws `UnsupportedBrowserError` without Web Locks.
   * @param {object} options
   * @param {number | string} options.ownId
   * @param {Push} options.push
   * @param {import("./signal-locks.mjs").Locks} [options.locks]
   * @param {IDBFactory} [options.factory]
   * @param {() => number} [options.now]
   * @returns {Promise<SignalClient>}
   */
  static async open({ ownId, push, locks, factory, now }) {
    const resolvedLocks = locks || webLocks()
    await deleteLegacyDb(factory).catch(() => {})
    const db = await openSignalDb(ownId, factory)
    return new SignalClient({ ownId, db, push, locks: resolvedLocks, now, factory })
  }

  close() {
    this.db.close()
  }

  /** Deletes all keys and local history of this session on this device. */
  async forgetDevice() {
    this.close()
    await deleteSignalDb(this.ownId, this.factory)
  }

  /** @returns {SignalStore} A fresh operation-scoped store. */
  operation() {
    return new SignalStore(this.db)
  }

  /**
   * @template T
   * @param {"shared" | "exclusive"} mode
   * @param {() => Promise<T>} fn
   * @returns {Promise<T>}
   */
  withKeysLock(mode, fn) {
    return this.locks.request(`privee-keys-${this.ownId}`, { mode }, fn)
  }

  /**
   * @template T
   * @param {number | string} peerId
   * @param {() => Promise<T>} fn
   * @returns {Promise<T>}
   */
  withPeerLock(peerId, fn) {
    return this.withKeysLock("shared", () =>
      this.locks.request(`privee-peer-${this.ownId}-${peerId}`, { mode: "exclusive" }, fn),
    )
  }

  /**
   * @param {string} event
   * @param {object} [payload]
   */
  async call(event, payload = {}) {
    const reply = await this.push(event, payload)
    if (!reply) throw new ServerError("no_reply")
    return reply
  }

  // -- Device state and key management ---------------------------------------

  /** @returns {Promise<DeviceState | undefined>} */
  deviceState() {
    return this.operation().get(Stores.meta, "device_state")
  }

  /**
   * @param {DeviceState} state
   * @returns {Promise<DeviceState>}
   */
  async setDeviceState(state) {
    const store = this.operation()
    store.put(Stores.meta, "device_state", state)
    await store.commit()
    return state
  }

  /** @returns {Promise<string | null>} Own identity key (base64). */
  async identityKey() {
    const keyPair = await this.operation().getIdentityKeyPair()
    return keyPair ? bufferToBase64(keyPair.pubKey) : null
  }

  /**
   * Reconciles local keys with the published bundle: publishes, rotates and
   * replenishes as needed.
   * @returns {Promise<DeviceState>}
   */
  ensureKeys() {
    return this.withKeysLock("exclusive", async () => {
      const status = await this.call("signal_status")
      if (status.error) throw new ServerError(status.error)

      const keyPair = await this.operation().getIdentityKeyPair()
      const serverKey = status.identity_key

      if (!keyPair) {
        if (serverKey) return this.setDeviceState("needs_reset")
        await this.publishNewIdentity("publish_identity", status)
        return this.setDeviceState("ready")
      }

      if (!serverKey) {
        await this.publishExistingIdentity(status)
        return this.setDeviceState("ready")
      }

      if (serverKey !== bufferToBase64(keyPair.pubKey)) return this.setDeviceState("superseded")

      await this.maintainKeys(status)
      return this.setDeviceState("ready")
    })
  }

  /**
   * Handles the server's `replenish_prekeys` request.
   * @returns {Promise<DeviceState>}
   */
  replenish() {
    return this.ensureKeys()
  }

  /**
   * Replaces the identity of this session with a new one generated on this
   * device. Other devices of the session become superseded, and every peer
   * session is rebuilt.
   * @returns {Promise<DeviceState>}
   */
  resetIdentity() {
    return this.withKeysLock("exclusive", async () => {
      await this.setDeviceState("resetting")
      const status = await this.call("signal_status")
      await this.publishNewIdentity("reset_identity", status)
      return this.setDeviceState("ready")
    })
  }

  /**
   * @param {"publish_identity" | "reset_identity"} event
   * @param {{max_opk_id?: number}} status
   */
  async publishNewIdentity(event, status) {
    const identity = await KeyHelper.generateIdentityKeyPair()
    const registrationId = KeyHelper.generateRegistrationId()
    const store = this.operation()

    if (event === "reset_identity") {
      for (const name of [Stores.identity, Stores.prekeys, Stores.signedPrekeys, Stores.sessions]) {
        store.clear(name)
      }
      await this.clearPeerSessionEpochs(store)
    }

    store.put(Stores.identity, "keyPair", identity)
    store.put(Stores.identity, "registrationId", registrationId)
    const signedPrekey = await this.createSignedPreKey(store, identity)
    const oneTimePrekeys = await this.createOneTimePreKeys(store, OPK_TARGET, status.max_opk_id)

    // Private keys are persisted before the public halves are published.
    await store.commit()

    const reply = await this.call(event, {
      identity_key: bufferToBase64(identity.pubKey),
      registration_id: registrationId,
      signed_prekey: signedPrekey,
      one_time_prekeys: oneTimePrekeys,
    })
    if (reply.error) throw new ServerError(reply.error)
  }

  /**
   * The server has no bundle (e.g. it was wiped) but this device has keys.
   * @param {{max_opk_id?: number}} status
   */
  async publishExistingIdentity(status) {
    const store = this.operation()
    const identity = await store.getIdentityKeyPair()
    if (!identity) throw new DeviceNotReadyError(undefined)
    const registrationId = await store.getLocalRegistrationId()
    const signedPrekey = await this.createSignedPreKey(store, identity)
    const oneTimePrekeys = await this.createOneTimePreKeys(store, OPK_TARGET, status.max_opk_id)
    await store.commit()

    const reply = await this.call("publish_identity", {
      identity_key: bufferToBase64(identity.pubKey),
      registration_id: registrationId,
      signed_prekey: signedPrekey,
      one_time_prekeys: oneTimePrekeys,
    })
    if (reply.error) throw new ServerError(reply.error)
  }

  /**
   * Rotates the signed prekey when due, prunes expired ones and replenishes
   * one-time prekeys below the low watermark.
   * @param {{identity_key: string, opk_count: number, max_opk_id: number, max_age_ms?: number}} status
   */
  async maintainKeys(status) {
    const now = this.now()
    const store = this.operation()
    const identity = await store.getIdentityKeyPair()
    if (!identity) return
    const identityKey = bufferToBase64(identity.pubKey)
    const current = await store.get(Stores.meta, "spk_current")

    if (!current || now - current.createdAt >= SPK_ROTATION_MS) {
      const signedPrekey = await this.createSignedPreKey(store, identity)
      await store.commit()
      const reply = await this.call("rotate_signed_prekey", {
        identity_key: identityKey,
        signed_prekey: signedPrekey,
      })
      if (reply.error) throw new ServerError(reply.error)
    }

    // Old signed prekeys stay available for PreKey messages still on the server.
    const retention = (status.max_age_ms || DEFAULT_MAX_AGE_MS) + DAY_MS
    const latest = await store.get(Stores.meta, "spk_current")
    const expired = (await store.getAll(Stores.signedPrekeys)).filter(
      (record) =>
        record.keyId !== latest?.keyId &&
        record.retiredAt !== undefined &&
        now - record.retiredAt > retention,
    )
    for (const record of expired) store.delete(Stores.signedPrekeys, record.keyId)
    await store.commit()

    if (status.opk_count < OPK_LOW_WATERMARK) {
      const oneTimePrekeys = await this.createOneTimePreKeys(
        store,
        OPK_TARGET - status.opk_count,
        status.max_opk_id,
      )
      await store.commit()
      const reply = await this.call("add_prekeys", {
        identity_key: identityKey,
        one_time_prekeys: oneTimePrekeys,
      })
      if (reply.error) throw new ServerError(reply.error)
    }
  }

  /**
   * @param {SignalStore} store
   * @param {import("@privacyresearch/libsignal-protocol-typescript").KeyPairType} identity
   */
  async createSignedPreKey(store, identity) {
    const keyId = ((await store.get(Stores.meta, "spk_counter")) || 0) + 1
    const signed = await KeyHelper.generateSignedPreKey(identity, keyId)
    const createdAt = this.now()

    // Retention of the previous key starts when it stops being published.
    const previous = await store.get(Stores.meta, "spk_current")
    const retired = previous && (await store.get(Stores.signedPrekeys, previous.keyId))
    if (retired)
      store.put(Stores.signedPrekeys, retired.keyId, { ...retired, retiredAt: createdAt })

    store.put(Stores.meta, "spk_counter", keyId)
    store.put(Stores.meta, "spk_current", { keyId, createdAt })
    store.put(Stores.signedPrekeys, keyId, {
      keyId,
      keyPair: signed.keyPair,
      signature: signed.signature,
      createdAt,
    })

    return {
      key_id: keyId,
      public_key: bufferToBase64(signed.keyPair.pubKey),
      signature: bufferToBase64(signed.signature),
    }
  }

  /**
   * Reserves `count` new one-time prekey ids, above any id ever used locally or
   * accepted by the server. Ids are never reused; gaps are harmless.
   * @param {SignalStore} store
   * @param {number} count
   * @param {number} [serverMaxId]
   */
  async createOneTimePreKeys(store, count, serverMaxId = 0) {
    const start = Math.max((await store.get(Stores.meta, "opk_counter")) || 0, serverMaxId || 0)
    const prekeys = []

    for (let keyId = start + 1; keyId <= start + count; keyId++) {
      const prekey = await KeyHelper.generatePreKey(keyId)
      store.put(Stores.prekeys, keyId, prekey.keyPair)
      prekeys.push({ key_id: keyId, public_key: bufferToBase64(prekey.keyPair.pubKey) })
    }

    store.put(Stores.meta, "opk_counter", start + count)
    return prekeys
  }

  /** @param {SignalStore} store */
  async clearPeerSessionEpochs(store) {
    const tx = this.db.transaction(Stores.meta, "readonly")
    const keys = await new Promise((resolve, reject) => {
      const request = tx.objectStore(Stores.meta).getAllKeys()
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })

    for (const key of /** @type {IDBValidKey[]} */ (keys)) {
      if (typeof key === "string" && key.startsWith("peer:")) {
        const meta = await store.get(Stores.meta, key)
        store.put(Stores.meta, key, { ...meta, sessionEpoch: null })
      }
    }
  }

  // -- Trust -----------------------------------------------------------------

  /**
   * @param {number | string} peerId
   * @returns {Promise<ArrayBuffer | undefined>} A changed, not yet approved identity key.
   */
  async pendingIdentity(peerId) {
    return (await this.operation().getTrust(String(peerId)))?.pendingKey
  }

  /**
   * @param {number | string} peerId
   * @param {ArrayBuffer} identityKey
   */
  async recordPendingIdentity(peerId, identityKey) {
    const store = this.operation()
    const trust = await store.getTrust(String(peerId))
    if (!trust || equalBuffers(trust.pendingKey, identityKey)) return
    store.put(Stores.trustedIdentities, String(peerId), { ...trust, pendingKey: identityKey })
    await store.commit()
  }

  /**
   * Accepts the pending identity of `peerId` and drops the old session, so the
   * next message rebuilds it from a fresh bundle.
   * @param {number | string} peerId
   */
  approveIdentity(peerId) {
    return this.withPeerLock(peerId, async () => {
      const store = this.operation()
      const trust = await store.getTrust(String(peerId))
      if (!trust?.pendingKey) return
      store.put(Stores.trustedIdentities, String(peerId), { publicKey: trust.pendingKey })
      await store.removeSession(addressOf(peerId).toString())
      const meta = (await store.get(Stores.meta, peerMetaKey(peerId))) || {}
      store.put(Stores.meta, peerMetaKey(peerId), { ...meta, sessionEpoch: null })
      await store.commit()
    })
  }

  /**
   * Safety number of the conversation, comparing both identity keys.
   * @param {number | string} peerId
   * @returns {Promise<string | null>}
   */
  async safetyNumber(peerId) {
    const store = this.operation()
    const identity = await store.getIdentityKeyPair()
    const trust = await store.getTrust(String(peerId))
    const peerKey = trust?.pendingKey || trust?.publicKey
    if (!identity || !peerKey) return null

    return new FingerprintGenerator(5200).createFor(
      String(this.ownId),
      identity.pubKey,
      String(peerId),
      peerKey,
    )
  }

  // -- Sessions --------------------------------------------------------------

  /** @returns {Promise<string>} The current conversation epoch. */
  async openConversation() {
    const reply = await this.call("open_conversation")
    if (!reply.epoch) throw new ServerError(reply.error || "no_epoch")
    return reply.epoch
  }

  /**
   * @param {SignalStore} store
   * @param {number | string} peerId
   */
  async buildSession(store, peerId) {
    const reply = await this.call("request_peer_bundle")
    if (reply.error || !reply.bundle) throw new NoPeerKeysError()

    const bundle = reply.bundle
    const identityKey = base64ToBuffer(bundle.identity_key)

    if (!(await store.isTrustedIdentity(String(peerId), identityKey))) {
      await this.recordPendingIdentity(peerId, identityKey)
      throw new IdentityChangedError(String(peerId), identityKey)
    }

    const address = addressOf(peerId)
    await store.removeSession(address.toString())

    await new SessionBuilder(store, address).processPreKey({
      identityKey,
      registrationId: bundle.registration_id,
      signedPreKey: {
        keyId: bundle.signed_prekey.key_id,
        publicKey: base64ToBuffer(bundle.signed_prekey.public_key),
        signature: base64ToBuffer(bundle.signed_prekey.signature),
      },
      preKey: bundle.one_time_prekey
        ? {
            keyId: bundle.one_time_prekey.key_id,
            publicKey: base64ToBuffer(bundle.one_time_prekey.public_key),
          }
        : undefined,
    })
  }

  /**
   * @param {SignalStore} store
   */
  async assertCanSend(store) {
    const state = await store.get(Stores.meta, "device_state")
    if (state !== "ready") throw new DeviceNotReadyError(state)
  }

  /**
   * Encrypts `plaintext` for `peerId` in `epoch` and queues it in the outbox,
   * atomically with the ratchet step. With `replaceNonce`, the outbox row is
   * replaced only if it is still pending: returns `null` when another flush
   * already delivered or re-encrypted it, so a message is never sent twice.
   * @param {number | string} peerId
   * @param {string} plaintext
   * @param {string} epoch
   * @param {{replaceNonce?: string, ts?: number, rebuild?: boolean}} [options]
   * @returns {Promise<OutboxRow | null>}
   */
  encryptMessage(peerId, plaintext, epoch, { replaceNonce, ts, rebuild = false } = {}) {
    return this.withPeerLock(peerId, async () => {
      const store = this.operation()
      await this.assertCanSend(store)
      if (replaceNonce && !(await store.get(Stores.pendingOutbox, replaceNonce))) return null

      const identity = await store.getIdentityKeyPair()
      if (!identity) throw new DeviceNotReadyError(undefined)
      const address = addressOf(peerId)
      const meta = (await store.get(Stores.meta, peerMetaKey(peerId))) || {}
      const session = await store.loadSession(address.toString())

      if (rebuild || !session || meta.sessionEpoch !== epoch) {
        await this.buildSession(store, peerId)
      }

      const ciphertext = await new SessionCipher(store, address).encrypt(utf8(plaintext))

      /** @type {OutboxRow} */
      const row = {
        nonce: crypto.randomUUID(),
        peerId: Number(peerId),
        type: /** @type {1 | 3} */ (ciphertext.type),
        body: btoa(/** @type {string} */ (ciphertext.body)),
        epoch,
        identityKey: bufferToBase64(identity.pubKey),
        plaintext,
        ts: ts ?? this.now(),
      }

      store.put(Stores.pendingOutbox, row.nonce, row)
      if (replaceNonce) store.delete(Stores.pendingOutbox, replaceNonce)
      store.put(Stores.meta, peerMetaKey(peerId), { ...meta, sessionEpoch: epoch })
      await store.commit()
      return row
    })
  }

  /**
   * Decrypts an incoming message and stores its plaintext in the local
   * history, atomically with the ratchet step. Returns the cached plaintext for
   * messages already processed, `null` for undecryptable messages.
   * Throws `IdentityChangedError` until a changed identity is approved.
   * @param {number | string} peerId
   * @param {ServerMessage} message
   * @returns {Promise<string | null>}
   */
  decryptMessage(peerId, message) {
    return this.withPeerLock(peerId, async () => {
      const store = this.operation()
      /** @type {HistoryRow | undefined} */
      const cached = await store.get(Stores.history, message.id)
      if (cached) return cached.plaintext

      if ((await store.get(Stores.meta, "device_state")) === "resetting") {
        throw new DeviceNotReadyError("resetting")
      }

      const address = addressOf(peerId)
      const meta = (await store.get(Stores.meta, peerMetaKey(peerId))) || {}
      const type = Number(message.type)

      // A PreKey message from a newer epoch starts a new session.
      if (type === 3 && meta.sessionEpoch && meta.sessionEpoch !== message.epoch) {
        await store.removeSession(address.toString())
      }

      /** @type {string | null} */
      let plaintext = null
      try {
        const cipher = new SessionCipher(store, address)
        const body = atob(message.body)
        const decrypted =
          type === 3
            ? await cipher.decryptPreKeyWhisperMessage(body, "binary")
            : await cipher.decryptWhisperMessage(body, "binary")
        plaintext = decoder.decode(decrypted)
      } catch (e) {
        store.discard()
        if (e instanceof IdentityChangedError) {
          await this.recordPendingIdentity(peerId, e.identityKey)
          throw e
        }
        console.warn("Unable to decrypt message", message.id, e)
      }

      const cursor =
        meta.cursor?.epoch === message.epoch
          ? { epoch: message.epoch, lastSeq: Math.max(meta.cursor.lastSeq, message.seq) }
          : { epoch: message.epoch, lastSeq: message.seq }

      /** @type {HistoryRow} */
      const row = {
        id: message.id,
        peerId: Number(peerId),
        epoch: message.epoch,
        seq: message.seq,
        direction: "in",
        plaintext,
        ts: this.now(),
      }

      store.put(Stores.history, row.id, row)
      store.put(Stores.meta, peerMetaKey(peerId), {
        ...meta,
        cursor,
        ...(type === 3 && plaintext !== null ? { sessionEpoch: message.epoch } : {}),
      })
      await store.commit()
      return plaintext
    })
  }

  // -- History and outbox ------------------------------------------------------

  /**
   * @param {string} id
   * @returns {Promise<HistoryRow | undefined>}
   */
  historyEntry(id) {
    return this.operation().get(Stores.history, id)
  }

  /**
   * @param {string} nonce
   * @returns {Promise<OutboxRow | undefined>}
   */
  outboxEntry(nonce) {
    return this.operation().get(Stores.pendingOutbox, nonce)
  }

  /**
   * @param {number | string} peerId
   * @returns {Promise<HistoryRow[]>} Local history, oldest first.
   */
  async history(peerId) {
    const id = Number(peerId)
    const rows = await this.operation().getAll(Stores.history, {
      index: "peer_ts",
      range: IDBKeyRange.bound([id, -Infinity], [id, Infinity]),
      filter: (row) => row.peerId === id,
    })
    return rows.sort((a, b) => a.ts - b.ts)
  }

  /**
   * @param {number | string} peerId
   * @returns {Promise<OutboxRow[]>} Pending messages, oldest first.
   */
  async pendingOutbox(peerId) {
    const id = Number(peerId)
    const rows = await this.operation().getAll(Stores.pendingOutbox, {
      index: "peer",
      range: IDBKeyRange.only(id),
      filter: (row) => row.peerId === id,
    })
    return rows.sort((a, b) => a.ts - b.ts)
  }

  /**
   * Moves an acknowledged outbox row into the history. Idempotent: it may run
   * for the send reply and for the stream entry carrying the same nonce.
   * @param {string} nonce
   * @param {{id: string, seq: number, epoch: string}} ack
   * @returns {Promise<HistoryRow | undefined>}
   */
  async acknowledge(nonce, { id, seq, epoch }) {
    const store = this.operation()
    /** @type {OutboxRow | undefined} */
    const row = await store.get(Stores.pendingOutbox, nonce)
    if (!row) return store.get(Stores.history, id)

    /** @type {HistoryRow} */
    const entry = {
      id,
      peerId: row.peerId,
      epoch,
      seq,
      direction: "out",
      plaintext: row.plaintext,
      ts: row.ts,
    }
    store.put(Stores.history, id, entry)
    store.delete(Stores.pendingOutbox, nonce)
    await store.commit()
    return entry
  }

  /**
   * @param {string} nonce
   */
  async dropOutboxEntry(nonce) {
    const store = this.operation()
    store.delete(Stores.pendingOutbox, nonce)
    await store.commit()
  }

  /**
   * Deletes the local history of the conversation with `peerId`.
   * @param {number | string} peerId
   */
  async clearHistory(peerId) {
    const rows = await this.history(peerId)
    const store = this.operation()
    for (const row of rows) store.delete(Stores.history, row.id)
    await store.commit()
  }

  /**
   * @param {number | string} peerId
   * @returns {Promise<{epoch: string, lastSeq: number} | undefined>}
   */
  async cursor(peerId) {
    return (await this.operation().get(Stores.meta, peerMetaKey(peerId)))?.cursor
  }

  // -- Sending -------------------------------------------------------------------

  /**
   * Encrypts, queues and delivers a message.
   * @param {number | string} peerId
   * @param {string} plaintext
   * @returns {Promise<HistoryRow | undefined>}
   */
  async send(peerId, plaintext) {
    const epoch = await this.openConversation()
    const row = /** @type {OutboxRow} */ (await this.encryptMessage(peerId, plaintext, epoch))
    try {
      return await this.deliver(row)
    } catch (e) {
      if (!(e instanceof ServerError && e.reason === "invalid")) markQueued(e)
      throw e
    }
  }

  /**
   * Delivers a queued row, re-encrypting it under a fresh session when the
   * conversation epoch changed.
   * @param {OutboxRow} row
   * @param {number} [attempt]
   * @returns {Promise<HistoryRow | undefined>}
   */
  async deliver(row, attempt = 0) {
    const reply = await this.call("send_message", {
      type: row.type,
      body: row.body,
      client_nonce: row.nonce,
      epoch: row.epoch,
      identity_key: row.identityKey,
    })

    if (reply.id) return this.acknowledge(row.nonce, reply)

    if (attempt + 1 >= MAX_SEND_ATTEMPTS) throw new ServerError(reply.error)

    switch (reply.error) {
      case "stale_epoch": {
        const next = await this.reencrypt(row, reply.epoch)
        return next ? this.deliver(next, attempt + 1) : undefined
      }

      case "in_flight":
        await sleep(250 * 2 ** attempt)
        return this.deliver(row, attempt + 1)

      case "superseded":
        if (row.identityKey !== (await this.identityKey())) {
          const next = await this.reencrypt(row, row.epoch)
          return next ? this.deliver(next, attempt + 1) : undefined
        }
        await this.setDeviceState("superseded")
        throw new DeviceNotReadyError("superseded")

      case "invalid":
        await this.dropOutboxEntry(row.nonce)
        throw new ServerError(reply.error)

      default:
        throw new ServerError(reply.error)
    }
  }

  /**
   * @param {OutboxRow} row
   * @param {string} epoch
   * @returns {Promise<OutboxRow | null>} `null` if the row is no longer pending.
   */
  reencrypt(row, epoch) {
    return this.encryptMessage(row.peerId, row.plaintext, epoch, {
      replaceNonce: row.nonce,
      ts: row.ts,
      rebuild: true,
    })
  }

  /**
   * Delivers every pending row for `peerId`. Rows are resent unchanged only if
   * they were encrypted for the current epoch and identity; otherwise they are
   * re-encrypted with a new nonce.
   * @param {number | string} peerId
   * @returns {Promise<Array<HistoryRow | undefined>>}
   */
  async flushOutbox(peerId) {
    const rows = await this.pendingOutbox(peerId)
    if (rows.length === 0) return []

    const epoch = await this.openConversation()
    const identityKey = await this.identityKey()
    const delivered = []

    for (const row of rows) {
      const current = row.epoch === epoch && row.identityKey === identityKey
      const next = current ? row : await this.reencrypt(row, epoch)
      if (next) delivered.push(await this.deliver(next))
    }
    return delivered
  }

  /**
   * Fetches and decrypts messages of `epoch` newer than the local cursor and
   * older than `untilSeq` (the first message rendered by the server stream).
   * @param {number | string} peerId
   * @param {string} epoch
   * @param {number | null} [untilSeq]
   */
  async catchUp(peerId, epoch, untilSeq = null) {
    const cursor = await this.cursor(peerId)
    let after = cursor?.epoch === epoch ? cursor.lastSeq : 0

    for (;;) {
      const reply = await this.call("fetch_messages", { epoch, after_seq: after })
      if (reply.error) throw new ServerError(reply.error)

      for (const message of /** @type {ServerMessage[]} */ (reply.messages)) {
        if (untilSeq !== null && message.seq >= untilSeq) return
        if (message.direction === "in") {
          try {
            await this.decryptMessage(peerId, message)
          } catch (e) {
            if (e instanceof IdentityChangedError) throw e
            console.warn("Catch-up decryption failed", e)
          }
        }
      }

      if (reply.next_cursor === null || reply.next_cursor === undefined) return
      after = reply.next_cursor
    }
  }
}
