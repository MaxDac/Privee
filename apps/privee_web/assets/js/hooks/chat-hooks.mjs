import { addChatInputHandler, decryptChatEntriesText, handlePreKeyBundle } from "../utils/chat.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { addDarkModeToggleHandlers } from "../utils/dark-mode-switcher.mjs"
import { pushFlash } from "../hooks/flash-hooks.mjs"
import { getPreKeyBundle, storePreKeyBundle } from "../utils/signal-store.mjs"
import { generateRegistrationKeys, exportPreKeyBundle } from "../utils/signal-protocol.mjs"
import {
  storeIdentityKeyPair,
  storeRegistrationId,
  storeSignedPreKey,
  storeOneTimePreKey,
} from "../utils/signal-store.mjs"

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
 * If no bundle exists (e.g., registration used old code), generates fresh keys.
 * @param {Function} pushEvent - LiveView pushEvent function
 */
const uploadOwnPreKeyBundle = async (pushEvent) => {
  console.debug("uploadOwnPreKeyBundle: starting")
  try {
    let bundle = await getPreKeyBundle()

    if (!bundle) {
      console.debug("No prekey bundle in IndexedDB - generating fresh keys")
      bundle = await generateFreshBundle()
    }

    if (!bundle) {
      console.error("Failed to generate or retrieve prekey bundle")
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

/**
 * Generates a fresh set of Signal Protocol keys and stores them in IndexedDB.
 * @returns {Promise<import("../utils/signal-protocol.mjs").PreKeyBundle|null>}
 */
const generateFreshBundle = async () => {
  try {
    const keys = await generateRegistrationKeys(10)

    await storeIdentityKeyPair(keys.identityKeyPair)
    await storeRegistrationId(keys.registrationId)
    await storeSignedPreKey(
      keys.signedPreKey.keyId,
      keys.signedPreKey.keyPair,
      keys.signedPreKey.signature,
    )

    for (const opk of keys.oneTimePreKeys) {
      await storeOneTimePreKey(opk.keyId, opk.keyPair)
    }

    const bundle = await exportPreKeyBundle(keys)
    await storePreKeyBundle(bundle)
    console.debug("Fresh Signal keys generated and stored")
    return bundle
  } catch (e) {
    console.error("Failed to generate fresh Signal keys:", e)
    return null
  }
}
