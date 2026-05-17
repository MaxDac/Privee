/**
 * Signal Protocol implementation using Web Crypto API.
 * Implements X3DH key agreement and Double Ratchet for per-message forward secrecy.
 *
 * Uses ECDH with P-256 curve (browser-supported) and AES-256-GCM for encryption.
 */

const CURVE = { name: "ECDH", namedCurve: "P-256" }
const ECDSA_CURVE = { name: "ECDSA", namedCurve: "P-256" }
const AES_GCM = { name: "AES-GCM", length: 256 }
const HKDF_HASH = "SHA-256"
const MAX_SKIP = 256

/**
 * @typedef {object} KeyPair
 * @property {CryptoKey} publicKey
 * @property {CryptoKey} privateKey
 */

/**
 * @typedef {object} ExportedKeyPair
 * @property {string} publicKey - Base64 encoded raw public key
 * @property {string} privateKey - Base64 encoded PKCS8 private key
 */

/**
 * @typedef {object} SignedPreKey
 * @property {number} keyId
 * @property {string} publicKey - Base64 encoded
 * @property {string} signature - Base64 encoded
 * @property {CryptoKey} [privateKey] - Local only, not exported
 */

/**
 * @typedef {object} PreKeyBundle
 * @property {string} identityKey - Base64 encoded public identity key
 * @property {number} registrationId
 * @property {SignedPreKey} signedPreKey
 * @property {Array<{keyId: number, publicKey: string}>} oneTimePreKeys
 */

/**
 * @typedef {object} SessionState
 * @property {CryptoKey} rootKey
 * @property {CryptoKey|null} sendingChainKey
 * @property {CryptoKey|null} receivingChainKey
 * @property {CryptoKeyPair|null} myRatchetKeyPair
 * @property {CryptoKey|null} theirRatchetPublicKey
 * @property {number} sendCount
 * @property {number} recvCount
 * @property {number} prevSendCount
 * @property {Map<string, CryptoKey>} skippedKeys
 */

// Utility: ArrayBuffer <-> Base64
/** @param {ArrayBuffer} buf */
const bufToBase64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
/** @param {string} b64 */
const base64ToBuf = (b64) => {
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

/**
 * Generates an ECDH key pair for use in X3DH / ratcheting.
 * @returns {Promise<CryptoKeyPair>}
 */
export const generateECDHKeyPair = () =>
  crypto.subtle.generateKey(CURVE, true, ["deriveKey", "deriveBits"])

/**
 * Generates an ECDSA key pair for signing (identity key).
 * @returns {Promise<CryptoKeyPair>}
 */
export const generateSigningKeyPair = () =>
  crypto.subtle.generateKey(ECDSA_CURVE, true, ["sign", "verify"])

/**
 * Exports a public key to base64.
 * @param {CryptoKey} key
 * @returns {Promise<string>}
 */
export const exportPublicKey = async (key) => {
  const raw = await crypto.subtle.exportKey("raw", key)
  return bufToBase64(raw)
}

/**
 * Imports a public key from base64.
 * @param {string} b64
 * @param {"ECDH"|"ECDSA"} type
 * @returns {Promise<CryptoKey>}
 */
export const importPublicKey = async (b64, type = "ECDH") => {
  const raw = base64ToBuf(b64)
  const algorithm = type === "ECDH" ? CURVE : ECDSA_CURVE
  const usages =
    type === "ECDH" ? /** @type {KeyUsage[]} */ ([]) : /** @type {KeyUsage[]} */ (["verify"])
  return await crypto.subtle.importKey("raw", raw, algorithm, true, usages)
}

/**
 * Exports a private key to base64.
 * @param {CryptoKey} key
 * @returns {Promise<string>}
 */
export const exportPrivateKey = async (key) => {
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", key)
  return bufToBase64(pkcs8)
}

/**
 * Imports a private key from base64.
 * @param {string} b64
 * @param {"ECDH"|"ECDSA"} type
 * @returns {Promise<CryptoKey>}
 */
export const importPrivateKey = async (b64, type = "ECDH") => {
  const pkcs8 = base64ToBuf(b64)
  const algorithm = type === "ECDH" ? CURVE : ECDSA_CURVE
  const usages =
    type === "ECDH"
      ? /** @type {KeyUsage[]} */ (["deriveKey", "deriveBits"])
      : /** @type {KeyUsage[]} */ (["sign"])
  return await crypto.subtle.importKey("pkcs8", pkcs8, algorithm, true, usages)
}

/**
 * Signs data with ECDSA.
 * @param {CryptoKey} privateKey
 * @param {ArrayBuffer} data
 * @returns {Promise<ArrayBuffer>}
 */
export const sign = (privateKey, data) =>
  crypto.subtle.sign({ name: "ECDSA", hash: HKDF_HASH }, privateKey, data)

/**
 * Verifies an ECDSA signature.
 * @param {CryptoKey} publicKey
 * @param {ArrayBuffer} signature
 * @param {ArrayBuffer} data
 * @returns {Promise<boolean>}
 */
export const verify = (publicKey, signature, data) =>
  crypto.subtle.verify({ name: "ECDSA", hash: HKDF_HASH }, publicKey, signature, data)

/**
 * Performs ECDH to derive shared bits.
 * @param {CryptoKey} privateKey - Our ECDH private key
 * @param {CryptoKey} publicKey - Their ECDH public key
 * @returns {Promise<ArrayBuffer>} - 256 bits of shared secret
 */
const ecdh = (privateKey, publicKey) =>
  crypto.subtle.deriveBits({ name: "ECDH", public: publicKey }, privateKey, 256)

/**
 * HKDF key derivation.
 * @param {ArrayBuffer} ikm - Input key material
 * @param {ArrayBuffer} salt
 * @param {ArrayBuffer} info
 * @returns {Promise<CryptoKey>} - AES-GCM key
 */
const hkdf = async (ikm, salt, info) => {
  const hkdfKey = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveKey"])
  return crypto.subtle.deriveKey(
    { name: "HKDF", hash: HKDF_HASH, salt, info },
    hkdfKey,
    AES_GCM,
    true,
    ["encrypt", "decrypt"],
  )
}

/**
 * KDF for ratcheting: derives two keys from a chain key.
 * @param {CryptoKey} chainKey
 * @returns {Promise<{messageKey: CryptoKey, nextChainKey: CryptoKey}>}
 */
const kdfChain = async (chainKey) => {
  const raw = await crypto.subtle.exportKey("raw", chainKey)
  const encoder = new TextEncoder()

  const messageKey = await hkdf(raw, new Uint8Array(32).buffer, encoder.encode("msg").buffer)
  const nextChainKeyRaw = await hkdf(raw, new Uint8Array(32).buffer, encoder.encode("chain").buffer)

  return { messageKey, nextChainKey: nextChainKeyRaw }
}

/**
 * KDF for root key ratchet: derives new root key and chain key from DH output.
 * @param {CryptoKey} rootKey
 * @param {ArrayBuffer} dhOutput
 * @returns {Promise<{newRootKey: CryptoKey, chainKey: CryptoKey}>}
 */
const kdfRootKey = async (rootKey, dhOutput) => {
  const rootKeyRaw = await crypto.subtle.exportKey("raw", rootKey)
  const encoder = new TextEncoder()

  const newRootKey = await hkdf(dhOutput, rootKeyRaw, encoder.encode("root").buffer)
  const chainKey = await hkdf(dhOutput, rootKeyRaw, encoder.encode("chain-init").buffer)

  return { newRootKey, chainKey }
}

// ====================== X3DH ======================

/**
 * Generates a complete set of Signal Protocol keys for registration.
 * @param {number} numOneTimePreKeys - Number of one-time prekeys to generate
 * @returns {Promise<{identityKeyPair: CryptoKeyPair, signedPreKey: {keyPair: CryptoKeyPair, keyId: number, signature: ArrayBuffer}, oneTimePreKeys: Array<{keyPair: CryptoKeyPair, keyId: number}>, registrationId: number}>}
 */
export const generateRegistrationKeys = async (numOneTimePreKeys = 10) => {
  const identityKeyPair = await generateSigningKeyPair()
  const registrationId = crypto.getRandomValues(new Uint32Array(1))[0]

  // Generate signed prekey (ECDH key signed by identity key)
  const signedPreKeyPair = await generateECDHKeyPair()
  const signedPreKeyPublicRaw = await crypto.subtle.exportKey("raw", signedPreKeyPair.publicKey)
  const signature = await sign(identityKeyPair.privateKey, signedPreKeyPublicRaw)

  const signedPreKey = {
    keyPair: signedPreKeyPair,
    keyId: 1,
    signature,
  }

  // Generate one-time prekeys
  const oneTimePreKeys = []
  for (let i = 0; i < numOneTimePreKeys; i++) {
    const keyPair = await generateECDHKeyPair()
    oneTimePreKeys.push({ keyPair, keyId: i + 1 })
  }

  return { identityKeyPair, signedPreKey, oneTimePreKeys, registrationId }
}

/**
 * Exports registration keys to a prekey bundle for uploading to the server.
 * @param {{identityKeyPair: CryptoKeyPair, signedPreKey: {keyPair: CryptoKeyPair, keyId: number, signature: ArrayBuffer}, oneTimePreKeys: Array<{keyPair: CryptoKeyPair, keyId: number}>, registrationId: number}} keys
 * @returns {Promise<PreKeyBundle>}
 */
export const exportPreKeyBundle = async (keys) => {
  const identityKey = await exportPublicKey(keys.identityKeyPair.publicKey)
  const signedPreKeyPublic = await exportPublicKey(keys.signedPreKey.keyPair.publicKey)

  const oneTimePreKeys = await Promise.all(
    keys.oneTimePreKeys.map(async (opk) => ({
      keyId: opk.keyId,
      publicKey: await exportPublicKey(opk.keyPair.publicKey),
    })),
  )

  return {
    identityKey,
    registrationId: keys.registrationId,
    signedPreKey: {
      keyId: keys.signedPreKey.keyId,
      publicKey: signedPreKeyPublic,
      signature: bufToBase64(keys.signedPreKey.signature),
    },
    oneTimePreKeys,
  }
}

/**
 * Performs X3DH as the initiator (Alice) to establish a shared secret with Bob.
 * @param {CryptoKey} myIdentityPrivateKey - Our identity private key (for ECDH derivation)
 * @param {{identity_key: string, signed_prekey: {public_key: string, signature: string}, one_time_prekey: {public_key: string}|null}} peerBundle - Peer's prekey bundle from server
 * @returns {Promise<{sharedSecret: CryptoKey, ephemeralPublicKey: string, usedOneTimePreKey: boolean}>}
 */
export const x3dhInitiate = async (myIdentityPrivateKey, peerBundle) => {
  // Import peer's keys
  const peerIdentityKey = await importPublicKey(peerBundle.identity_key, "ECDSA")
  const peerSignedPreKey = await importPublicKey(peerBundle.signed_prekey.public_key, "ECDH")

  // Verify signed prekey signature
  const signedPreKeyRaw = base64ToBuf(peerBundle.signed_prekey.public_key)
  const signatureRaw = base64ToBuf(peerBundle.signed_prekey.signature)
  const valid = await verify(peerIdentityKey, signatureRaw, signedPreKeyRaw)
  if (!valid) throw new Error("Signed prekey signature verification failed")

  // Generate ephemeral key pair
  const ephemeralKeyPair = await generateECDHKeyPair()

  // We need the identity key as ECDH-capable for DH computations
  // Re-derive an ECDH key from the identity key material
  const myIdentityECDH = await deriveECDHFromIdentity(myIdentityPrivateKey)

  // DH1: Identity(ours) <-> SignedPreKey(theirs)
  const dh1 = await ecdh(myIdentityECDH, peerSignedPreKey)
  // DH2: Ephemeral(ours) <-> Identity(theirs) - need peer identity as ECDH
  // Note: Since peer identity is ECDSA, we derive DH from ephemeral<->signedPreKey instead
  // Standard X3DH: DH1=IK_A,SPK_B | DH2=EK_A,IK_B | DH3=EK_A,SPK_B
  // Simplified for Web Crypto (ECDSA identity can't do ECDH): DH1=IK_A,SPK_B | DH2=EK_A,SPK_B
  const dh2 = await ecdh(ephemeralKeyPair.privateKey, peerSignedPreKey)

  let ikm = concatBuffers([dh1, dh2])

  // DH3: Ephemeral(ours) <-> OneTimePreKey(theirs) if available
  let usedOneTimePreKey = false
  if (peerBundle.one_time_prekey && peerBundle.one_time_prekey.public_key) {
    const peerOPK = await importPublicKey(peerBundle.one_time_prekey.public_key, "ECDH")
    const dh3 = await ecdh(ephemeralKeyPair.privateKey, peerOPK)
    ikm = concatBuffers([dh1, dh2, dh3])
    usedOneTimePreKey = true
  }

  // Derive shared secret via HKDF
  const encoder = new TextEncoder()
  const sharedSecret = await hkdf(ikm, new Uint8Array(32).buffer, encoder.encode("x3dh").buffer)

  const ephemeralPublicKey = await exportPublicKey(ephemeralKeyPair.publicKey)

  return { sharedSecret, ephemeralPublicKey, usedOneTimePreKey }
}

/**
 * Performs X3DH as the responder (Bob) to derive the same shared secret.
 * @param {CryptoKey} myIdentityPrivateKey - Our identity private key
 * @param {CryptoKey} mySignedPreKeyPrivate - Our signed prekey private key
 * @param {CryptoKey|null} myOneTimePreKeyPrivate - Our one-time prekey private key (if used)
 * @param {string} peerIdentityKeyB64 - Peer's identity public key (base64)
 * @param {string} peerEphemeralKeyB64 - Peer's ephemeral public key (base64)
 * @returns {Promise<CryptoKey>} - Shared secret
 */
export const x3dhRespond = async (
  myIdentityPrivateKey,
  mySignedPreKeyPrivate,
  myOneTimePreKeyPrivate,
  peerIdentityKeyB64,
  peerEphemeralKeyB64,
) => {
  const peerIdentityECDH = await importPublicKey(peerIdentityKeyB64, "ECDH")
  const peerEphemeralKey = await importPublicKey(peerEphemeralKeyB64, "ECDH")

  // DH1: SignedPreKey(ours) <-> Identity(theirs)
  const dh1 = await ecdh(mySignedPreKeyPrivate, peerIdentityECDH)
  // DH2: SignedPreKey(ours) <-> Ephemeral(theirs)
  const dh2 = await ecdh(mySignedPreKeyPrivate, peerEphemeralKey)

  let ikm = concatBuffers([dh1, dh2])

  // DH3: OneTimePreKey(ours) <-> Ephemeral(theirs)
  if (myOneTimePreKeyPrivate) {
    const dh3 = await ecdh(myOneTimePreKeyPrivate, peerEphemeralKey)
    ikm = concatBuffers([dh1, dh2, dh3])
  }

  const encoder = new TextEncoder()
  return hkdf(ikm, new Uint8Array(32).buffer, encoder.encode("x3dh").buffer)
}

// ====================== Double Ratchet ======================

/**
 * Initializes a sending session (after X3DH as initiator).
 * @param {CryptoKey} sharedSecret - From X3DH
 * @param {string} peerSignedPreKeyB64 - Peer's signed prekey (first ratchet public key)
 * @returns {Promise<SessionState>}
 */
export const initSendingSession = async (sharedSecret, peerSignedPreKeyB64) => {
  const theirRatchetPublicKey = await importPublicKey(peerSignedPreKeyB64, "ECDH")
  const myRatchetKeyPair = await generateECDHKeyPair()

  const dhOutput = await ecdh(myRatchetKeyPair.privateKey, theirRatchetPublicKey)
  const rootKeyRaw = await crypto.subtle.exportKey("raw", sharedSecret)
  const encoder = new TextEncoder()

  const newRootKey = await hkdf(dhOutput, rootKeyRaw, encoder.encode("root").buffer)
  const sendingChainKey = await hkdf(dhOutput, rootKeyRaw, encoder.encode("chain-init").buffer)

  return {
    rootKey: newRootKey,
    sendingChainKey,
    receivingChainKey: null,
    myRatchetKeyPair,
    theirRatchetPublicKey,
    sendCount: 0,
    recvCount: 0,
    prevSendCount: 0,
    skippedKeys: new Map(),
  }
}

/**
 * Initializes a receiving session (after X3DH as responder).
 * @param {CryptoKey} sharedSecret - From X3DH
 * @param {CryptoKeyPair} mySignedPreKeyPair - Our signed prekey pair (first ratchet key)
 * @returns {SessionState}
 */
export const initReceivingSession = (sharedSecret, mySignedPreKeyPair) => ({
  rootKey: sharedSecret,
  sendingChainKey: null,
  receivingChainKey: null,
  myRatchetKeyPair: mySignedPreKeyPair,
  theirRatchetPublicKey: null,
  sendCount: 0,
  recvCount: 0,
  prevSendCount: 0,
  skippedKeys: new Map(),
})

/**
 * Encrypts a message using the Double Ratchet.
 * @param {SessionState} session
 * @param {string} plaintext
 * @returns {Promise<{ciphertext: string, header: string}>}
 */
export const ratchetEncrypt = async (session, plaintext) => {
  if (!session.sendingChainKey) {
    throw new Error("Session not initialized for sending")
  }

  const { messageKey, nextChainKey } = await kdfChain(session.sendingChainKey)
  session.sendingChainKey = nextChainKey

  // Create header: our ratchet public key + message number + prev chain length
  const myRatchetPubB64 = await exportPublicKey(
    /** @type {CryptoKeyPair} */ (session.myRatchetKeyPair).publicKey,
  )
  const header = JSON.stringify({
    ratchetKey: myRatchetPubB64,
    n: session.sendCount,
    pn: session.prevSendCount,
  })

  session.sendCount++

  // Encrypt with AES-GCM
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const encoder = new TextEncoder()
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: encoder.encode(header) },
    messageKey,
    encoder.encode(plaintext),
  )

  const ciphertext = bufToBase64(concatBuffers([iv.buffer, encrypted]))

  return { ciphertext, header }
}

/**
 * Decrypts a message using the Double Ratchet.
 * @param {SessionState} session
 * @param {string} ciphertextB64
 * @param {string} headerStr
 * @returns {Promise<string>}
 */
export const ratchetDecrypt = async (session, ciphertextB64, headerStr) => {
  const header = JSON.parse(headerStr)
  const { ratchetKey, n, pn } = header

  // Check skipped keys first
  const skipKey = `${ratchetKey}:${n}`
  if (session.skippedKeys.has(skipKey)) {
    const messageKey = /** @type {CryptoKey} */ (session.skippedKeys.get(skipKey))
    session.skippedKeys.delete(skipKey)
    return decryptWithKey(messageKey, ciphertextB64, headerStr)
  }

  // Check if we need a DH ratchet step
  const theirCurrentPub = session.theirRatchetPublicKey
    ? await exportPublicKey(session.theirRatchetPublicKey)
    : null

  if (ratchetKey !== theirCurrentPub) {
    // Skip any missed messages in the current receiving chain
    if (session.receivingChainKey) {
      await skipMessages(session, pn)
    }

    // DH ratchet step
    await dhRatchetStep(session, ratchetKey)
  }

  // Skip missed messages in the new receiving chain
  await skipMessages(session, n)

  // Derive message key
  const { messageKey, nextChainKey } = await kdfChain(
    /** @type {CryptoKey} */ (session.receivingChainKey),
  )
  session.receivingChainKey = nextChainKey
  session.recvCount++

  return decryptWithKey(messageKey, ciphertextB64, headerStr)
}

/**
 * Performs a DH ratchet step when receiving a new ratchet key.
 * @param {SessionState} session
 * @param {string} newRatchetKeyB64
 */
const dhRatchetStep = async (session, newRatchetKeyB64) => {
  session.prevSendCount = session.sendCount
  session.sendCount = 0
  session.recvCount = 0

  session.theirRatchetPublicKey = await importPublicKey(newRatchetKeyB64, "ECDH")

  // Derive receiving chain
  const dhRecv = await ecdh(
    /** @type {CryptoKeyPair} */ (session.myRatchetKeyPair).privateKey,
    session.theirRatchetPublicKey,
  )
  const { newRootKey: rootKey1, chainKey: recvChain } = await kdfRootKey(session.rootKey, dhRecv)
  session.rootKey = rootKey1
  session.receivingChainKey = recvChain

  // Generate new ratchet key pair and derive sending chain
  session.myRatchetKeyPair = await generateECDHKeyPair()
  const dhSend = await ecdh(session.myRatchetKeyPair.privateKey, session.theirRatchetPublicKey)
  const { newRootKey: rootKey2, chainKey: sendChain } = await kdfRootKey(session.rootKey, dhSend)
  session.rootKey = rootKey2
  session.sendingChainKey = sendChain
}

/**
 * Skips messages and stores their keys for later decryption.
 * @param {SessionState} session
 * @param {number} until - Message number to skip up to
 */
const skipMessages = async (session, until) => {
  if (!session.receivingChainKey) return
  if (until - session.recvCount > MAX_SKIP) {
    throw new Error("Too many skipped messages")
  }

  while (session.recvCount < until) {
    const { messageKey, nextChainKey } = await kdfChain(session.receivingChainKey)
    session.receivingChainKey = nextChainKey

    const theirPub = await exportPublicKey(/** @type {CryptoKey} */ (session.theirRatchetPublicKey))
    session.skippedKeys.set(`${theirPub}:${session.recvCount}`, messageKey)
    session.recvCount++
  }
}

/**
 * Decrypts ciphertext with a message key.
 * @param {CryptoKey} messageKey
 * @param {string} ciphertextB64
 * @param {string} headerStr
 * @returns {Promise<string>}
 */
const decryptWithKey = async (messageKey, ciphertextB64, headerStr) => {
  const raw = base64ToBuf(ciphertextB64)
  const iv = raw.slice(0, 12)
  const ciphertext = raw.slice(12)
  const encoder = new TextEncoder()

  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, additionalData: encoder.encode(headerStr) },
    messageKey,
    ciphertext,
  )

  return new TextDecoder().decode(decrypted)
}

// ====================== Helpers ======================

/**
 * Concatenates array buffers.
 * @param {ArrayBuffer[]} buffers
 * @returns {ArrayBuffer}
 */
const concatBuffers = (buffers) => {
  const totalLength = buffers.reduce((sum, buf) => sum + buf.byteLength, 0)
  const result = new Uint8Array(totalLength)
  let offset = 0
  for (const buf of buffers) {
    result.set(new Uint8Array(buf), offset)
    offset += buf.byteLength
  }
  return result.buffer
}

/**
 * Derives an ECDH-capable key from an ECDSA identity private key.
 * We generate a deterministic ECDH key by using the ECDSA key material.
 * In practice, we export and re-import as ECDH.
 * @param {CryptoKey} ecdsaPrivateKey
 * @returns {Promise<CryptoKey>}
 */
const deriveECDHFromIdentity = async (ecdsaPrivateKey) => {
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", ecdsaPrivateKey)
  return crypto.subtle.importKey("pkcs8", pkcs8, CURVE, false, ["deriveKey", "deriveBits"])
}

// ====================== Serialization ======================

/**
 * Serializes session state for IndexedDB storage.
 * @param {SessionState} session
 * @returns {Promise<object>}
 */
export const serializeSession = async (session) => {
  const myRatchetPub = session.myRatchetKeyPair
    ? await exportPublicKey(session.myRatchetKeyPair.publicKey)
    : null
  const myRatchetPriv = session.myRatchetKeyPair
    ? await exportPrivateKey(session.myRatchetKeyPair.privateKey)
    : null
  const theirRatchetPub = session.theirRatchetPublicKey
    ? await exportPublicKey(session.theirRatchetPublicKey)
    : null

  const rootKeyRaw = await crypto.subtle.exportKey("raw", session.rootKey)
  const sendChainRaw = session.sendingChainKey
    ? await crypto.subtle.exportKey("raw", session.sendingChainKey)
    : null
  const recvChainRaw = session.receivingChainKey
    ? await crypto.subtle.exportKey("raw", session.receivingChainKey)
    : null

  const skippedEntries = []
  for (const [key, val] of session.skippedKeys) {
    const raw = await crypto.subtle.exportKey("raw", val)
    skippedEntries.push([key, bufToBase64(raw)])
  }

  return {
    rootKey: bufToBase64(rootKeyRaw),
    sendingChainKey: sendChainRaw ? bufToBase64(sendChainRaw) : null,
    receivingChainKey: recvChainRaw ? bufToBase64(recvChainRaw) : null,
    myRatchetPublicKey: myRatchetPub,
    myRatchetPrivateKey: myRatchetPriv,
    theirRatchetPublicKey: theirRatchetPub,
    sendCount: session.sendCount,
    recvCount: session.recvCount,
    prevSendCount: session.prevSendCount,
    skippedKeys: skippedEntries,
  }
}

/**
 * Deserializes session state from IndexedDB storage.
 * @param {Record<string, any>} data
 * @returns {Promise<SessionState>}
 */
export const deserializeSession = async (data) => {
  /** @param {string} b64 */
  const importAESKey = (b64) =>
    crypto.subtle.importKey("raw", base64ToBuf(b64), AES_GCM, true, ["encrypt", "decrypt"])

  const rootKey = await importAESKey(data.rootKey)
  const sendingChainKey = data.sendingChainKey ? await importAESKey(data.sendingChainKey) : null
  const receivingChainKey = data.receivingChainKey
    ? await importAESKey(data.receivingChainKey)
    : null

  let myRatchetKeyPair = null
  if (data.myRatchetPublicKey && data.myRatchetPrivateKey) {
    const publicKey = await importPublicKey(data.myRatchetPublicKey, "ECDH")
    const privateKey = await importPrivateKey(data.myRatchetPrivateKey, "ECDH")
    myRatchetKeyPair = { publicKey, privateKey }
  }

  const theirRatchetPublicKey = data.theirRatchetPublicKey
    ? await importPublicKey(data.theirRatchetPublicKey, "ECDH")
    : null

  const skippedKeys = new Map()
  for (const [key, val] of data.skippedKeys || []) {
    skippedKeys.set(key, await importAESKey(val))
  }

  return {
    rootKey,
    sendingChainKey,
    receivingChainKey,
    myRatchetKeyPair,
    theirRatchetPublicKey,
    sendCount: data.sendCount,
    recvCount: data.recvCount,
    prevSendCount: data.prevSendCount,
    skippedKeys,
  }
}

export const testExports = {
  bufToBase64,
  base64ToBuf,
  concatBuffers,
  kdfChain,
  kdfRootKey,
  deriveECDHFromIdentity,
}
