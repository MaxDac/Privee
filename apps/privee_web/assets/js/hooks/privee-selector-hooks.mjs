import { pushFlash } from "./flash-hooks.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { renderConversations } from "../utils/conversation-list.mjs"
import { openHintEditor } from "../utils/hint-editor.mjs"
import { openClientFor } from "../utils/signal-hook-utils.mjs"

/**
 * Renders the conversations held on this browser, with their local hints.
 * @param {HTMLElement} container
 * @param {import("../utils/signal-client.mjs").SignalClient} client
 */
export const showLocalConversations = async (container, client) => {
  const conversations = await client.listConversations()
  renderConversations(container, conversations, {
    onEditHint: async (conversation) => {
      const result = await openHintEditor(container.ownerDocument, { current: conversation.hint })
      if (!result) return
      await client.setPeerHint(conversation.peerId, result.action === "save" ? result.hint : null)
      await showLocalConversations(container, client)
    },
  })
}

/**
 * Adds hooks to the privee selector screen.
 * @param {any} Hooks LiveView Hooks
 */
export function addPriveeSelectorHooks(Hooks) {
  Hooks.PriveeSelectorScreen = {
    /** @this {any} */
    async mounted() {
      const pushEvent = this.pushEvent.bind(this)
      addSessionNameCopyListener(pushFlash(pushEvent))

      const ownId = this.el.dataset.ownSessionId
      if (!ownId) return

      // Publishes (or maintains) this session's Signal keys, so peers can reach
      // it before it opens a chat. Failures are reported by the chat screen.
      try {
        this.client = await openClientFor(this, ownId)
        if (this.destroyedFlag) return this.client.close()
        this.handleEvent("replenish_prekeys", () => this.client?.replenish().catch(console.warn))

        const container = this.el.querySelector("#local-conversations")
        if (container) {
          await showLocalConversations(container, this.client).catch((e) =>
            console.warn("Unable to list local conversations", e),
          )
        }

        await this.client.ensureKeys()
      } catch (e) {
        console.warn("Unable to set up encryption keys", e)
      }
    },

    /** @this {any} */
    destroyed() {
      this.destroyedFlag = true
      this.client?.close()
      this.client = null
    },
  }
}
