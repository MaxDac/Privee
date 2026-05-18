/**
 * Chat encryption and input handling using Signal Protocol (Double Ratchet).
 */

import { querySelectorArrayOf } from "./dom-utils.mjs"
import {
  x3dhInitiate,
  initSendingSession,
  ratchetEncrypt,
  ratchetDecrypt,
} from "./signal-protocol.mjs"
import { getIdentityKeyPair, getSession, storeSession } from "./signal-store.mjs"

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
 * @typedef {object} PreKeyBundleEvent
 * @property {{peer_session_id: string|null, identity_key: string, registration_id: number, signed_prekey: {key_id: number, public_key: string, signature: string}, one_time_prekey: {key_id: number, public_key: string}|null}} detail
 */

/**
 * Handles the prekey bundle event from the backend to establish a Signal session.
 * @param {PreKeyBundleEvent & Event} e
 * @returns {Promise<void>}
 */
export const handlePreKeyBundle = async (e) => {
  const { peer_session_id, identity_key, signed_prekey, one_time_prekey } = e.detail

  if (!peer_session_id) {
    console.warn("No prekey bundle available for peer - waiting for peer to come online")
    currentSession = null
    currentPeerSessionId = null
    return
  }

  console.debug("Processing prekey bundle for peer:", peer_session_id)
  currentPeerSessionId = String(peer_session_id)

  // Check if we already have a session with this peer
  const existingSession = await getSession(currentPeerSessionId)
  if (existingSession) {
    currentSession = existingSession
    console.debug("Loaded existing Signal session for peer", currentPeerSessionId)
    return
  }

  // Establish new session via X3DH
  const identityKeyPair = await getIdentityKeyPair()
  if (!identityKeyPair) {
    console.error("No identity key pair found - registration incomplete")
    return
  }

  try {
    const peerBundle = {
      identity_key,
      signed_prekey,
      one_time_prekey,
    }

    const { sharedSecret } = await x3dhInitiate(identityKeyPair.privateKey, peerBundle)

    currentSession = await initSendingSession(sharedSecret, signed_prekey.public_key)
    await storeSession(currentPeerSessionId, currentSession)
    console.debug("Established new Signal session with peer", currentPeerSessionId)
  } catch (err) {
    console.error("Failed to establish Signal session:", err)
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

  if (!currentSession) {
    console.error("No Signal session established")
    return
  }

  try {
    const { ciphertext, header } = await ratchetEncrypt(currentSession, text)
    ciphertextInput.value = ciphertext
    headerInput.value = header
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

  if (!currentSession) {
    return Promise.resolve()
  }

  const promises = uncoveredChatEntries.map((ce) =>
    decryptChatEntryText(/** @type {HTMLElement} */ (ce)),
  )
  await Promise.all(promises)

  // Persist session state after decryption (ratchet may have advanced)
  if (currentPeerSessionId) {
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
    const decryptedMessage = await ratchetDecrypt(
      /** @type {import("./signal-protocol.mjs").SessionState} */ (currentSession),
      ciphertext,
      header,
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

  decryptChatEntryText,
}
