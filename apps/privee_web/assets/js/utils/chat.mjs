/**
 * Chat encryption and input handling using Signal Protocol (Double Ratchet).
 */

import { querySelectorArrayOf } from "./dom-utils.mjs"
import {
  x3dhInitiate,
  x3dhRespond,
  initSendingSession,
  initReceivingSession,
  ratchetEncrypt,
  ratchetDecrypt,
  exportPublicKey,
} from "./signal-protocol.mjs"
import {
  getIdentityKeyPair,
  getSignedPreKey,
  getOneTimePreKey,
  removeOneTimePreKey,
  getSession,
  storeSession,
} from "./signal-store.mjs"

const chatFormSelector = "#chat-form"
const chatTextInputSelector = "#chat-text"
const ciphertextHiddenInputSelector = "#chat-ciphertext"
const headerHiddenInputSelector = "#chat-header"

// prettier-ignore
const chatEntryUnconverted="[data-converted=\"false\"]"

/** @type {import("./signal-protocol.mjs").SessionState | null} */
var currentSession = null
/** @type {string | null} */
var currentPeerSessionId = null
/** @type {Map<string, string>} Map of ciphertext to plaintext for sent messages */
const sentMessages = new Map()

/**
 * Stored peer prekey bundle for lazy session initiation (X3DH happens on first send).
 * @type {{identity_key: string, signed_prekey: {key_id: number, public_key: string, signature: string}, one_time_prekey: {key_id: number, public_key: string}|null} | null}
 */
var pendingPeerBundle = null

/**
 * @typedef {object} PreKeyBundleEvent
 * @property {{peer_session_id: string|null, identity_key: string, registration_id: number, signed_prekey: {key_id: number, public_key: string, signature: string}, one_time_prekey: {key_id: number, public_key: string}|null}} detail
 */

/**
 * Handles the prekey bundle event from the backend.
 * Stores the bundle for lazy session initiation (X3DH on first send).
 * If a receiving session already exists, loads it instead.
 * @param {PreKeyBundleEvent & Event} e
 * @returns {Promise<void>}
 */
export const handlePreKeyBundle = async (e) => {
  const { peer_session_id, identity_key, signed_prekey, one_time_prekey } = e.detail

  if (!peer_session_id) {
    console.warn("No prekey bundle available for peer - waiting for peer to come online")
    currentSession = null
    currentPeerSessionId = null
    pendingPeerBundle = null
    return
  }

  console.debug("Processing prekey bundle for peer:", peer_session_id)
  currentPeerSessionId = String(peer_session_id)

  // Check if we already have a session with this peer
  const existingSession = await getSession(currentPeerSessionId)
  if (existingSession) {
    // Only use the stored session if no concurrent operation (e.g. decryption) has already
    // established an in-memory session. The in-memory session may be more up-to-date than
    // what was persisted at the time getSession() was called.
    if (!currentSession) {
      currentSession = existingSession
      console.debug("Loaded existing Signal session for peer", currentPeerSessionId)
    }
    pendingPeerBundle = null
    return
  }

  // Store the bundle — session will be established on first send or first receive
  pendingPeerBundle = { identity_key, signed_prekey, one_time_prekey }
  console.debug("Stored peer prekey bundle for lazy session initiation")
}

/**
 * Establishes a sending session on first message send (X3DH initiator role).
 * @returns {Promise<boolean>} True if session was established successfully
 */
const establishSendingSession = async () => {
  if (!pendingPeerBundle || !currentPeerSessionId) {
    return false
  }

  const identityKeyPair = await getIdentityKeyPair()
  if (!identityKeyPair) {
    console.error("No identity key pair found - registration incomplete")
    return false
  }

  try {
    const { sharedSecret, ephemeralPublicKey, usedOneTimePreKey } = await x3dhInitiate(
      identityKeyPair.privateKey,
      pendingPeerBundle,
    )

    const myIdentityPubB64 = await exportPublicKey(identityKeyPair.publicKey)

    currentSession = await initSendingSession(
      sharedSecret,
      pendingPeerBundle.signed_prekey.public_key,
    )

    // Store prekey message info for inclusion in first message header
    currentSession._preKeyInfo = {
      identityKey: myIdentityPubB64,
      ephemeralKey: ephemeralPublicKey,
      usedOPKId: usedOneTimePreKey ? (pendingPeerBundle.one_time_prekey?.key_id ?? null) : null,
    }

    await storeSession(currentPeerSessionId, currentSession)
    pendingPeerBundle = null
    console.debug("Established sending session with peer", currentPeerSessionId)
    return true
  } catch (err) {
    console.error("Failed to establish Signal session:", err)
    return false
  }
}

/**
 * Establishes a receiving session from a PreKey message (X3DH responder role).
 * @param {object} preKeyInfo - PreKey info from the message header
 * @param {string} preKeyInfo.identityKey - Sender's identity public key
 * @param {string} preKeyInfo.ephemeralKey - Sender's ephemeral public key
 * @param {number|null} preKeyInfo.usedOPKId - Which one-time prekey was consumed
 * @returns {Promise<boolean>}
 */
const establishReceivingSession = async (preKeyInfo) => {
  const identityKeyPair = await getIdentityKeyPair()
  if (!identityKeyPair) {
    console.error("No identity key pair found - cannot establish receiving session")
    return false
  }

  const signedPreKey = await getSignedPreKey(1)
  if (!signedPreKey) {
    console.error("No signed prekey found - cannot establish receiving session")
    return false
  }

  let oneTimePreKeyPrivate = null
  if (preKeyInfo.usedOPKId != null) {
    const opk = await getOneTimePreKey(preKeyInfo.usedOPKId)
    if (opk) {
      oneTimePreKeyPrivate = opk.privateKey
      await removeOneTimePreKey(preKeyInfo.usedOPKId)
    }
  }

  try {
    const sharedSecret = await x3dhRespond(
      identityKeyPair.privateKey,
      signedPreKey.privateKey,
      oneTimePreKeyPrivate,
      preKeyInfo.identityKey,
      preKeyInfo.ephemeralKey,
    )

    currentSession = initReceivingSession(sharedSecret, {
      publicKey: signedPreKey.publicKey,
      privateKey: signedPreKey.privateKey,
    })

    if (currentPeerSessionId) {
      await storeSession(currentPeerSessionId, currentSession)
    }

    console.debug("Established receiving session from PreKey message")
    return true
  } catch (err) {
    console.error("Failed to establish receiving session:", err)
    return false
  }
}

/**
 * Handles the chat input by encrypting with Signal Protocol.
 * @param {KeyboardEvent} e
 * @returns {Promise<void>}
 */
export const handleChatInput = async (e) => {
  if (e.key !== "Enter") {
    return
  }

  e.preventDefault()

  const formElement = /** @type {HTMLFormElement} */ (document.querySelector(chatFormSelector))
  const chatTextInput = /** @type {HTMLInputElement} */ (
    document.querySelector(chatTextInputSelector)
  )
  const ciphertextInput = /** @type {HTMLInputElement} */ (
    document.querySelector(ciphertextHiddenInputSelector)
  )
  const headerInput = /** @type {HTMLInputElement} */ (
    document.querySelector(headerHiddenInputSelector)
  )

  const text = chatTextInput.value

  if (text == null || text === "") {
    ciphertextInput.value = ""
    headerInput.value = ""
    return
  }

  // Establish session on first send if needed
  if (!currentSession && pendingPeerBundle) {
    const established = await establishSendingSession()
    if (!established) {
      console.error("Failed to establish Signal session for sending")
      return
    }
  }

  if (!currentSession) {
    console.warn(
      "No Signal session established - peer has not registered their encryption keys yet. " +
        "The peer needs to open the chat page at least once.",
    )
    return
  }

  try {
    const { ciphertext, header } = await ratchetEncrypt(currentSession, text)

    // If this is the first message, include PreKey info in the header
    let finalHeader = header
    if (currentSession._preKeyInfo) {
      const headerObj = JSON.parse(header)
      headerObj.preKey = currentSession._preKeyInfo
      finalHeader = JSON.stringify(headerObj)
      // Clear preKey info after first message
      delete currentSession._preKeyInfo
    }

    ciphertextInput.value = ciphertext
    headerInput.value = finalHeader
    chatTextInput.value = ""

    // Store plaintext so we can display our own sent messages without decryption
    sentMessages.set(ciphertext, text)

    // Persist session state after encryption (ratchet advanced)
    if (currentPeerSessionId) {
      await storeSession(currentPeerSessionId, currentSession)
    }

    formElement.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
  } catch (err) {
    console.error("Failed to encrypt message:", err)
  }
}

/**
 * Adds the chat input handler to the chat form.
 */
export const addChatInputHandler = () => {
  const chatTextInput = /** @type {HTMLInputElement} */ (
    document.querySelector(chatTextInputSelector)
  )
  chatTextInput.removeEventListener("keypress", handleChatInput)
  chatTextInput.addEventListener("keypress", handleChatInput)
}

/**
 * Decrypts all unconverted chat entries using the Signal session.
 * @param {string} _sessionName - The current session name (kept for API compat).
 */
export const decryptChatEntriesText = async (_sessionName) => {
  const uncoveredChatEntries = querySelectorArrayOf(chatEntryUnconverted)

  if (uncoveredChatEntries.length === 0) {
    return Promise.resolve()
  }

  // Process entries sequentially to handle PreKey messages and maintain ratchet order
  for (const ce of uncoveredChatEntries) {
    await decryptChatEntryText(/** @type {HTMLElement} */ (ce))
  }

  // Persist session state after decryption (ratchet may have advanced)
  if (currentPeerSessionId && currentSession) {
    await storeSession(currentPeerSessionId, currentSession)
  }
}

/**
 * Decrypts a single chat entry element.
 * @param {HTMLElement} chatEntry
 * @returns {Promise<void>}
 */
const decryptChatEntryText = async (chatEntry) => {
  const ciphertext = chatEntry.dataset.ciphertext
  const header = chatEntry.dataset.header

  if (!ciphertext || !header) {
    return
  }

  // Sent messages (data-message="from") can't be decrypted with our ratchet
  // Use the locally cached plaintext instead
  if (chatEntry.dataset.message === "from") {
    const plaintext = sentMessages.get(ciphertext)
    if (plaintext) {
      chatEntry.textContent = `${plaintext}\u200E`
      chatEntry.setAttribute("data-converted", "true")
      chatEntry.classList.remove("hidden")
    }
    return
  }

  try {
    // Check if this is a PreKey message requiring session establishment
    const headerObj = JSON.parse(header)
    if (headerObj.preKey && !currentSession) {
      const established = await establishReceivingSession(headerObj.preKey)
      if (!established) {
        console.error("Failed to establish receiving session from PreKey message")
        return
      }
    }

    if (!currentSession) {
      return
    }

    // Strip preKey info from header before passing to ratchetDecrypt
    const ratchetHeader = headerObj.preKey
      ? JSON.stringify({ ratchetKey: headerObj.ratchetKey, n: headerObj.n, pn: headerObj.pn })
      : header

    const decryptedMessage = await ratchetDecrypt(
      /** @type {import("./signal-protocol.mjs").SessionState} */ (currentSession),
      ciphertext,
      ratchetHeader,
    )
    chatEntry.textContent = `${decryptedMessage}\u200E`
    chatEntry.setAttribute("data-converted", "true")
    chatEntry.classList.remove("hidden")
  } catch (err) {
    console.error("Failed to decrypt message:", err)
  }
}

export const testExports = {
  /**
   * Gets the current session.
   * @returns {import("./signal-protocol.mjs").SessionState | null}
   */
  getCurrentSession: () => currentSession,

  /**
   * Sets the current session (for testing).
   * @param {import("./signal-protocol.mjs").SessionState | null} session
   */
  setCurrentSession: (session) => {
    currentSession = session
  },

  /**
   * Sets the current peer session ID (for testing).
   * @param {string | null} id
   */
  setCurrentPeerSessionId: (id) => {
    currentPeerSessionId = id
  },

  /**
   * Sets the pending peer bundle (for testing).
   * @param {any} bundle
   */
  setPendingPeerBundle: (bundle) => {
    pendingPeerBundle = bundle
  },

  decryptChatEntryText,
}
