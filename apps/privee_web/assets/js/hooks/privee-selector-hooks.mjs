import { pushFlash } from "./flash-hooks.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"

/**
 * Adds hooks to the privee selector screen.
 * @param {any} Hooks LiveView Hooks
 */
export function addPriveeSelectorHooks(Hooks) {
  Hooks.PriveeSelectorScreen = {
    mounted() {
      //@ts-ignore
      const pushEvent = this.pushEvent.bind(this)
      console.debug("Adding privee selector hooks")
      addSessionNameCopyListener(pushFlash(pushEvent))
    },
  }
}
