import { addChatInputHandler } from "../utils/chat.mjs"
import { addSessionNameCopyListener } from "../utils/clipboard.mjs"
import { addDarkModeToggleHandlers } from "../utils/dark-mode-switcher.mjs"

/**
 * Adds hooks to the chat screen to automatically scroll to the bottom of the chat.
 * @param {any} Hooks LiveView Hooks
 */
export function addChatHooks(Hooks) {
  Hooks.ChatScreen = {
    mounted() {
      // Readding the event listener for the chat menu buttons.
      addSessionNameCopyListener()
      addDarkModeToggleHandlers()
      addChatInputHandler()
      scrollElementToEnd(this.el)
    },
    updated() {
      scrollElementToEnd(this.el)
    },
  }

  /**
   * Scrolls the element to the end of the scroll.
   * @param {HTMLElement} element The element to scroll.
   */
  const scrollElementToEnd = (element) => (element.scrollTop = element.scrollHeight)
}
