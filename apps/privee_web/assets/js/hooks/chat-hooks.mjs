import { addChatInputHandler, decryptChatEntriesText, handlePreKeyBundle } from "../utils/chat.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { addDarkModeToggleHandlers } from "../utils/dark-mode-switcher.mjs"
import { pushFlash } from "../hooks/flash-hooks.mjs"
import { getPreKeyBundle } from "../utils/signal-store.mjs"

/**
 * @typedef {object} ChatScreenHook
 * @property {HTMLElement} el - The DOM element the hook is attached to
 * @property {Function} pushEvent - Function for sending events back to the LiveView server
 * @property {Function} handleEvent - Function for handling events from the LiveView server
 * @property {Function} handleChat - Async handler that decrypts chat entries for the current session and scrolls the chat to the latest entry
 */

/**
 * Adds hooks to the chat screen to automatically scroll to the bottom of the chat.
 * @param {any} Hooks LiveView Hooks
 */
export const addChatHooks = (Hooks) => {
  Hooks.ChatScreen = {
    /**
     * @this {ChatScreenHook}
     */
    mounted() {
      const targetSessionName = this.el.dataset.selectedSessionName
      if (targetSessionName) {
        window.name = `privee-chat-${targetSessionName}`
      }

      // Readding the event listener for the chat menu buttons.
      const pushEvent = this.pushEvent.bind(this)
      addSessionNameCopyListener(pushFlash(pushEvent))
      addDarkModeToggleHandlers()
      addChatInputHandler()

      // Handle prekey bundle from server for Signal session establishment (for late-arriving bundles via PubSub)
      this.handleEvent("prekey_bundle", (/** @type {any} */ data) => {
        console.debug("Received prekey_bundle event from server:", data)
        handlePreKeyBundle(/** @type {any} */ ({ detail: data }))
      })

      // Process initial prekey bundle from data attribute (avoids race condition with async hook loading)
      const peerBundleJson = this.el.dataset.peerPrekeyBundle
      if (peerBundleJson) {
        try {
          const bundleData = JSON.parse(peerBundleJson)
          console.debug("Processing initial prekey bundle from data attribute:", bundleData)
          handlePreKeyBundle(/** @type {any} */ ({ detail: bundleData }))
        } catch (e) {
          console.error("Failed to parse initial prekey bundle:", e)
        }
      }

      // Upload our own prekey bundle to the server so peers can establish sessions
      uploadOwnPreKeyBundle(pushEvent)

      this.handleChat()
    },

    /**
     * @this {ChatScreenHook}
     */
    updated() {
      this.handleChat()
    },

    /**
     * @this {ChatScreenHook}
     */
    async handleChat() {
      const sessionName = this.el.dataset.sessionName

      if (!sessionName) {
        return
      }

      try {
        await decryptChatEntriesText(sessionName)
        scrollElementToEnd(this.el)
        console.debug("Decryption done")
      } catch (e) {
        console.error("An error in the decryption of the chats happened", e)
      }
    },
  }
}

/**
 * Scrolls the element to the end of the scroll.
 * @param {HTMLElement} element The element to scroll.
 */
const scrollElementToEnd = (element) => (element.scrollTop = element.scrollHeight)

/**
 * Loads the stored prekey bundle from IndexedDB and uploads it to the server.
 * @param {Function} pushEvent - LiveView pushEvent function
 */
const uploadOwnPreKeyBundle = async (pushEvent) => {
  console.debug("uploadOwnPreKeyBundle: starting")
  try {
    const bundle = await getPreKeyBundle()
    console.debug("uploadOwnPreKeyBundle: got bundle from IndexedDB:", !!bundle)
    if (!bundle) {
      console.warn("No prekey bundle found in IndexedDB - registration may be incomplete")
      return
    }

    console.debug("Uploading own prekey bundle to server")
    pushEvent("register_prekeys", {
      identity_key: bundle.identityKey,
      registration_id: bundle.registrationId,
      signed_prekey: {
        key_id: bundle.signedPreKey.keyId,
        public_key: bundle.signedPreKey.publicKey,
        signature: bundle.signedPreKey.signature,
      },
      one_time_prekeys: bundle.oneTimePreKeys.map((pk) => ({
        key_id: pk.keyId,
        public_key: pk.publicKey,
      })),
    })
  } catch (e) {
    console.error("Failed to upload prekey bundle:", e)
  }
}
