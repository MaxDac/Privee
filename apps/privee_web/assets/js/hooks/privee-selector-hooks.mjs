import { pushFlash } from "./flash-hooks.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { openClientFor } from "../utils/signal-hook-utils.mjs"

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
