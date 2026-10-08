import { ChatController } from "../utils/chat.mjs"
import { clientText } from "../utils/locale.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { addDarkModeToggleHandlers } from "../utils/dark-mode-switcher.mjs"
import { UnsupportedBrowserError } from "../utils/signal-locks.mjs"
import { openClientFor } from "../utils/signal-hook-utils.mjs"
import { pushFlash } from "./flash-hooks.mjs"

/**
 * @typedef {object} ChatScreenHook
 * @property {HTMLElement} el The `#chat-screen` element.
 * @property {Function} pushEvent
 * @property {Function} handleEvent
 * @property {ChatController | null} [controller]
 * @property {boolean} [destroyedFlag]
 */

/**
 * Adds the ChatScreen hook.
 * @param {any} Hooks LiveView Hooks
 */
export const addChatHooks = (Hooks) => {
  Hooks.ChatScreen = {
    /** @this {ChatScreenHook} */
    async mounted() {
      const { selectedSessionName, ownSessionId, peerSessionId } = this.el.dataset
      if (selectedSessionName) window.name = `privee-chat-${selectedSessionName}`

      addSessionNameCopyListener(pushFlash(this.pushEvent.bind(this)))
      addDarkModeToggleHandlers()

      if (!ownSessionId || !peerSessionId) return

      let client
      try {
        client = await openClientFor(this, ownSessionId)
      } catch (e) {
        showStartupError(
          this.el,
          e instanceof UnsupportedBrowserError ? "unsupported" : "failedToStart",
        )
        console.error("Unable to open the Signal store", e)
        return
      }

      if (this.destroyedFlag) {
        client.close()
        return
      }

      const controller = new ChatController({ el: this.el, client, peerId: Number(peerSessionId) })
      this.controller = controller

      this.handleEvent("peer_keys_ready", () => controller.onPeerKeysReady())
      this.handleEvent("replenish_prekeys", () => controller.onReplenish())
      this.handleEvent("identity_superseded", (/** @type {any} */ payload) =>
        controller.onIdentitySuperseded(payload),
      )

      await controller.start()
    },

    /** @this {ChatScreenHook} */
    updated() {
      this.controller?.processEntries()
    },

    /** @this {ChatScreenHook} */
    destroyed() {
      this.destroyedFlag = true
      this.controller?.destroy()
      this.controller?.client.close()
      this.controller = null
    },
  }
}

/**
 * @param {HTMLElement} el
 * @param {string} key
 */
const showStartupError = (el, key) => {
  const container = el.ownerDocument.getElementById("chat-banner")
  if (!container) return
  const banner = el.ownerDocument.createElement("div")
  banner.id = "chat-banner-error"
  banner.setAttribute("role", "alert")
  banner.className =
    "my-2 rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-900 dark:border-red-700 dark:bg-red-950 dark:text-red-100"
  banner.dataset.clientText = key
  banner.textContent = clientText(key, el.ownerDocument)
  container.replaceChildren(banner)
}
