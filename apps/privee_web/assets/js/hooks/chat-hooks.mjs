import { addChatInputHandler, decryptChatEntriesText } from "../utils/chat.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { addDarkModeToggleHandlers } from "../utils/dark-mode-switcher.mjs"
import { pushFlash } from "../hooks/flash-hooks.mjs"

/**
 * @typedef {object} ChatScreenHook
 * @property {HTMLElement} el - The DOM element the hook is attached to
 * @property {Function} pushEvent - Function for sending events back to the LiveView server
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
      // Readding the event listener for the chat menu buttons.
      const pushEvent = this.pushEvent.bind(this)
      addSessionNameCopyListener(pushFlash(pushEvent))
      addDarkModeToggleHandlers()
      addChatInputHandler()
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
