import { pushFlash } from "./flash-hooks.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"

/**
 * Adds hooks to the bauta selector screen.
 * @param {any} Hooks LiveView Hooks
 */
export function addBautaSelectorHooks(Hooks) {
  Hooks.BautaSelectorScreen = {
    mounted() {
      // @ts-ignore: `this.pushEvent` is provided by the LiveView hook context at runtime and is not known to TypeScript.
      const pushEvent = this.pushEvent.bind(this)

      addSessionNameCopyListener(pushFlash(pushEvent))
    },
  }
}
