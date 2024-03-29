/**
 * @typedef {object} SessionsPublicKey The payload of the event that sends the
 * public key of the session to the server.
 * @property {string} current The current session public key in string format.
 * @property {string} selected The selected session public key in string format.
 */

import { encryptMessage, importStringPublicKey } from "./security.mjs"

const chatFormSelector = "#chat-form"
const chatTextInputSelector = "#chat-text"
const fromHiddenInputSelector = "#text-from"
const toHiddenInputSelector = "#text-to"

/**
 * @typedef {object & Event} SessionsPublicKeyEvent The event that sends the
 * public keys of the two sessions of the chat page.
 * @property {SessionsPublicKey} detail The payload of the event.
 */

var currentPublicKey = null
var selectedPublicKey = null

/**
 * Handles the event that sends the public keys of the two sessions of the chat/
 * @param {SessionsPublicKeyEvent} e The event payload.
 * @returns {Promise<void>} A promise that resolves when the public key is stored.
 */
export const handleSendingPrivateKey = async (e) => {
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

  /** @type {HTMLFormElement} */ const formElement = document.querySelector(chatFormSelector)
  /** @type {HTMLInputElement} */ const chatTextInput =
    document.querySelector(chatTextInputSelector)
  /** @type {HTMLInputElement} */ const fromHiddenInput =
    document.querySelector(fromHiddenInputSelector)
  /** @type {HTMLInputElement} */ const toHiddenInput =
    document.querySelector(toHiddenInputSelector)

  const text = chatTextInput.value

  if (text == null || text === "") {
    fromHiddenInput.value = ""
    toHiddenInput.value = ""
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
  /** @type {HTMLInputElement} */ const chatTextInput =
    document.querySelector(chatTextInputSelector)
  chatTextInput.addEventListener("keypress", handleChatInput)
}

export const testExports = {
  /**
   * Gets the current public key.
   * @returns {CryptoKey} The current public key.
   */
  getCurrentPublicKey: () => currentPublicKey,

  /**
   * Gets the selected public key.
   * @returns {CryptoKey} The selected public key.
   */
  getSelectedPublicKey: () => selectedPublicKey,
}
