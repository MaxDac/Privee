/**
 * Adds hooks to the chat screen to automatically scroll to the bottom of the chat.
 * @param {any} Hooks LiveView Hooks 
 */
export function addChatHooks(Hooks) { 
  Hooks.ChatScreen = {
    mounted() {
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
  const scrollElementToEnd = (element) => element.scrollTop = element.scrollHeight
}