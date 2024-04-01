import { addChatInputHandler, decryptChatEntriesText } from "../utils/chat.mjs"
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
      this.handleChat()
    },
    updated() {
      this.handleChat()
    },
    handleChat() {
      const sessionName = this.el.dataset.sessionName
      decryptChatEntriesText(sessionName)
        .then(() => scrollElementToEnd(this.el))
        .then(() => console.debug("Decryption done"))
        .catch((e) => console.error("An error in the decryption of the chats happened", e))
    },
  }

  /**
   * Scrolls the element to the end of the scroll.
   * @param {HTMLElement} element The element to scroll.
   */
  const scrollElementToEnd = (element) => (element.scrollTop = element.scrollHeight)
}
