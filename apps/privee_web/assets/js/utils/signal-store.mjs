/**
 * Signal Protocol key store backed by IndexedDB.
 * Manages identity keys, signed prekeys, one-time prekeys, and session state.
 */

import { storeObject, getObject, deleteObject } from "./front-end-database.mjs"
import {
  exportPublicKey,
  exportPrivateKey,
  importPublicKey,
  importPrivateKey,
  serializeSession,
  deserializeSession,
} from "./signal-protocol.mjs"

const DB_NAME = "SignalKeyStore"
const KEYS_TABLE = "signal_keys"
const SESSIONS_TABLE = "signal_sessions"

const KEY_IDENTITY = "identity_key_pair"
const KEY_REGISTRATION_ID = "registration_id"
const KEY_SIGNED_PREKEY_PREFIX = "signed_prekey_"
const KEY_ONE_TIME_PREKEY_PREFIX = "one_time_prekey_"
const KEY_SESSION_PREFIX = "session_"

/**
 * Stores the identity key pair.
 * @param {CryptoKeyPair} keyPair
 */
export const storeIdentityKeyPair = async (keyPair) => {
  const exported = {
    publicKey: await exportPublicKey(keyPair.publicKey),
    privateKey: await exportPrivateKey(keyPair.privateKey),
  }
  await storeObject(DB_NAME, KEYS_TABLE, KEY_IDENTITY, exported)
}

/**
 * Retrieves the identity key pair.
 * @returns {Promise<{publicKey: CryptoKey, privateKey: CryptoKey}|null>}
 */
export const getIdentityKeyPair = async () => {
  const data = await getObject(DB_NAME, KEYS_TABLE, KEY_IDENTITY)
  if (!data) return null

  return {
    publicKey: await importPublicKey(data.publicKey, "ECDSA"),
    privateKey: await importPrivateKey(data.privateKey, "ECDSA"),
  }
}

/**
 * Stores the registration ID.
 * @param {number} id
 */
export const storeRegistrationId = async (id) => {
  await storeObject(DB_NAME, KEYS_TABLE, KEY_REGISTRATION_ID, id)
}

/**
 * Retrieves the registration ID.
 * @returns {Promise<number|null>}
 */
export const getRegistrationId = async () => {
  return await getObject(DB_NAME, KEYS_TABLE, KEY_REGISTRATION_ID)
}

/**
 * Stores a signed prekey.
 * @param {number} keyId
 * @param {CryptoKeyPair} keyPair
 * @param {ArrayBuffer} signature
 */
export const storeSignedPreKey = async (keyId, keyPair, signature) => {
  const exported = {
    keyId,
    publicKey: await exportPublicKey(keyPair.publicKey),
    privateKey: await exportPrivateKey(keyPair.privateKey),
    signature: btoa(String.fromCharCode(...new Uint8Array(signature))),
  }
  await storeObject(DB_NAME, KEYS_TABLE, `${KEY_SIGNED_PREKEY_PREFIX}${keyId}`, exported)
}

/**
 * Retrieves a signed prekey.
 * @param {number} keyId
 * @returns {Promise<{publicKey: CryptoKey, privateKey: CryptoKey, signature: ArrayBuffer}|null>}
 */
export const getSignedPreKey = async (keyId) => {
  const data = await getObject(DB_NAME, KEYS_TABLE, `${KEY_SIGNED_PREKEY_PREFIX}${keyId}`)
  if (!data) return null

  const binary = atob(data.signature)
  const sigBytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) sigBytes[i] = binary.charCodeAt(i)

  return {
    publicKey: await importPublicKey(data.publicKey, "ECDH"),
    privateKey: await importPrivateKey(data.privateKey, "ECDH"),
    signature: sigBytes.buffer,
  }
}

/**
 * Stores a one-time prekey.
 * @param {number} keyId
 * @param {CryptoKeyPair} keyPair
 */
export const storeOneTimePreKey = async (keyId, keyPair) => {
  const exported = {
    keyId,
    publicKey: await exportPublicKey(keyPair.publicKey),
    privateKey: await exportPrivateKey(keyPair.privateKey),
  }
  await storeObject(DB_NAME, KEYS_TABLE, `${KEY_ONE_TIME_PREKEY_PREFIX}${keyId}`, exported)
}

/**
 * Retrieves a one-time prekey.
 * @param {number} keyId
 * @returns {Promise<{publicKey: CryptoKey, privateKey: CryptoKey}|null>}
 */
export const getOneTimePreKey = async (keyId) => {
  const data = await getObject(DB_NAME, KEYS_TABLE, `${KEY_ONE_TIME_PREKEY_PREFIX}${keyId}`)
  if (!data) return null

  return {
    publicKey: await importPublicKey(data.publicKey, "ECDH"),
    privateKey: await importPrivateKey(data.privateKey, "ECDH"),
  }
}

/**
 * Removes a one-time prekey (consumed after use).
 * @param {number} keyId
 */
export const removeOneTimePreKey = async (keyId) => {
  await deleteObject(DB_NAME, KEYS_TABLE, `${KEY_ONE_TIME_PREKEY_PREFIX}${keyId}`)
}

/**
 * Stores a ratchet session state for a peer.
 * @param {string} peerSessionId
 * @param {import("./signal-protocol.mjs").SessionState} session
 */
export const storeSession = async (peerSessionId, session) => {
  const serialized = await serializeSession(session)
  await storeObject(DB_NAME, SESSIONS_TABLE, `${KEY_SESSION_PREFIX}${peerSessionId}`, serialized)
}

/**
 * Retrieves a ratchet session state for a peer.
 * @param {string} peerSessionId
 * @returns {Promise<import("./signal-protocol.mjs").SessionState|null>}
 */
export const getSession = async (peerSessionId) => {
  const data = await getObject(DB_NAME, SESSIONS_TABLE, `${KEY_SESSION_PREFIX}${peerSessionId}`)
  if (!data) return null
  return deserializeSession(data)
}

/**
 * Removes a session for a peer.
 * @param {string} peerSessionId
 */
export const removeSession = async (peerSessionId) => {
  await deleteObject(DB_NAME, SESSIONS_TABLE, `${KEY_SESSION_PREFIX}${peerSessionId}`)
}

const KEY_PREKEY_BUNDLE = "prekey_bundle"

/**
 * Stores the exported public prekey bundle (for re-uploading to server on chat mount).
 * @param {import("./signal-protocol.mjs").PreKeyBundle} bundle
 */
export const storePreKeyBundle = async (bundle) => {
  await storeObject(DB_NAME, KEYS_TABLE, KEY_PREKEY_BUNDLE, bundle)
}

/**
 * Retrieves the stored public prekey bundle.
 * @returns {Promise<import("./signal-protocol.mjs").PreKeyBundle|null>}
 */
export const getPreKeyBundle = async () => {
  return await getObject(DB_NAME, KEYS_TABLE, KEY_PREKEY_BUNDLE)
}
