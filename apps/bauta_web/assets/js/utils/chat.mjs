/**
 * @typedef {object} SessionsPublicKey The payload of the event that sends the
 * public key of the session to the server.
 * @property {string} current The current session public key in string format.
 * @property {string} selected The selected session public key in string format.
 */

import { querySelectorArrayOf } from "./dom-utils.mjs"
import { getPrivateKey, importStringPublicKey } from "./security.mjs"
import { decryptMessage, encryptMessage } from "./message-encryption.mjs"

const chatFormSelector = "#chat-form"
const chatTextInputSelector = "#chat-text"
const fromHiddenInputSelector = "#text-from"
const toHiddenInputSelector = "#text-to"

// prettier-ignore
const chatEntryUnconverted="[data-converted=\"false\"]"

/**
 * @typedef {{detail: SessionsPublicKey} & Event} SessionsPublicKeyEvent The event that sends the
 * public keys of the two sessions of the chat page.
 */

/** @type {CryptoKey | null} */
var currentPublicKey = null
/** @type {CryptoKey | null} */
var selectedPublicKey = null

/**
 * Handles the event that sends the public keys of the two sessions of the chat.
 * @param {SessionsPublicKeyEvent} e The event payload.
 * @returns {Promise<void>} A promise that resolves when the public key is stored.
 */
export const handleSendingPublicKey = async (e) => {
  const { current, selected } = e.detail
  currentPublicKey = await importStringPublicKey(current)
  selectedPublicKey = await importStringPublicKey(selected)
}

/**
 * Handles the chat input by encrypting the content of the text input, and then
 * putting the values into the related hidden inputs.
 * @param {KeyboardEvent} e The submit event.
 * @returns {Promise<void>} The result of the operation.
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
  const fromHiddenInput = /** @type {HTMLInputElement} */ (
    document.querySelector(fromHiddenInputSelector)
  )
  const toHiddenInput = /** @type {HTMLInputElement} */ (
    document.querySelector(toHiddenInputSelector)
  )

  const text = chatTextInput.value

  if (text == null || text === "") {
    fromHiddenInput.value = ""
    toHiddenInput.value = ""
    return
  }

  if (!currentPublicKey || !selectedPublicKey) {
    return
  }

  const encryptedFrom = await encryptMessage(text, currentPublicKey)
  const encryptedTo = await encryptMessage(text, selectedPublicKey)

  fromHiddenInput.value = encryptedFrom
  toHiddenInput.value = encryptedTo
  chatTextInput.value = ""

  formElement.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
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
 * Converts all the chat entries whose text is still in base64 encrypted format into normal
 * chat entries.
 * @param {string} sessionName The current session name.
 */
export const decryptChatEntriesText = async (sessionName) => {
  const uncoveredChatEntries = querySelectorArrayOf(chatEntryUnconverted)

  if (uncoveredChatEntries.length === 0) {
    return Promise.resolve()
  }

  const privateKey = await getPrivateKey(sessionName)

  if (!privateKey) {
    return Promise.resolve()
  }

  const promises = uncoveredChatEntries.map((ce) =>
    decryptChatEntryText(/** @type {HTMLElement} */ (ce), privateKey),
  )
  await Promise.all(promises)
}

/**
 * Removes trailing invisible characters from encrypted chat entry text.
 * @param {HTMLElement} chatEntry - The chat entry HTML element containing encrypted text.
 * @returns {string} The cleaned encrypted text string with trailing invisible characters removed.
 */
const cleanEncryptedString = (chatEntry) => {
  const initialTrimmed = chatEntry.innerHTML.trim()

  const withoutInvisibleChar = initialTrimmed.endsWith("\u200E")
    ? initialTrimmed.slice(0, -1)
    : initialTrimmed

  return withoutInvisibleChar.trim()
}

/**
 * Re-adds the trailing invisible character (U+200E) to a decrypted message.
 * This character is used as a marker to indicate processed chat entries.
 * @param {string} decryptedMessage - The decrypted message text.
 * @returns {string} The decrypted message with the trailing invisible character appended.
 */
const reAddTrailingChar = (decryptedMessage) => `${decryptedMessage}\u200E`

/**
 * Converts a single chat entry element text by decrypting it.
 * @param {HTMLElement} chatEntry The chat entry HTML element.
 * @param {CryptoKey} privateKey The private key with which the chat text can be decrypted.
 * @returns {Promise<string | void>} The execution result.
 */
const decryptChatEntryText = async (chatEntry, privateKey) => {
  const encryptedText = cleanEncryptedString(chatEntry)
  const decryptedMessage = await decryptMessage(encryptedText, privateKey)
  chatEntry.innerHTML = reAddTrailingChar(decryptedMessage)
  chatEntry.setAttribute("data-converted", "true")
  chatEntry.classList.remove("hidden")
}

export const testExports = {
  /**
   * Gets the current public key.
   * @returns {CryptoKey | null} The current public key.
   */
  getCurrentPublicKey: () => currentPublicKey,

  /**
   * Gets the selected public key.
   * @returns {CryptoKey | null} The selected public key.
   */
  getSelectedPublicKey: () => selectedPublicKey,

  decryptChatEntryText,

  cleanEncryptedString,

  reAddTrailingChar,
}
