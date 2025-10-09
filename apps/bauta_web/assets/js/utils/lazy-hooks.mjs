/**
 * Lazy loading utilities for Phoenix LiveView hooks.
 * This module provides functions to create lazy-loaded hook wrappers
 * that only load their dependencies when the hook is actually mounted.
 */

/**
 * Creates a lazy-loaded wrapper for the ChatScreen hook.
 * Only loads chat functionality when the hook is mounted on a page.
 * @returns {object} The lazy-loaded ChatScreen hook
 */
export const createLazyChatScreenHook = () => ({
  async mounted() {
    // Dynamic import - only loads when this hook is used
    const { addChatHooks } = await import("../hooks/chat-hooks.mjs")

    // Create temporary hooks object
    const tempHooks = {}
    addChatHooks(tempHooks)

    // Transfer the ChatScreen methods to this instance
    const chatScreenHook = tempHooks.ChatScreen
    if (chatScreenHook) {
      // Copy mounted, updated, and other lifecycle methods
      this.__mounted = chatScreenHook.mounted
      this.__updated = chatScreenHook.updated
      this.__handleChat = chatScreenHook.handleChat

      // Call the actual mounted function
      if (this.__mounted) {
        await this.__mounted.call(this)
      }
    }
  },

  async updated() {
    if (this.__updated) {
      await this.__updated.call(this)
    }
  },

  async handleChat() {
    if (this.__handleChat) {
      await this.__handleChat.call(this)
    }
  },
})

/**
 * Creates a lazy-loaded wrapper for the RegistrationScreen hook.
 * Only loads registration functionality when the hook is mounted on a page.
 * @returns {object} The lazy-loaded RegistrationScreen hook
 */
export const createLazyRegistrationScreenHook = () => ({
  async mounted() {
    const { addRegistrationHooks } = await import("../hooks/registration-hooks.mjs")

    const tempHooks = {}
    addRegistrationHooks(tempHooks)

    const regScreenHook = tempHooks.RegistrationScreen
    if (regScreenHook && regScreenHook.mounted) {
      await regScreenHook.mounted.call(this)
    }
  },
})

/**
 * Creates a lazy-loaded wrapper for the BautaSelectorScreen hook.
 * Only loads selector functionality when the hook is mounted on a page.
 * @returns {object} The lazy-loaded BautaSelectorScreen hook
 */
export const createLazyBautaSelectorScreenHook = () => ({
  async mounted() {
    const { addBautaSelectorHooks } = await import("../hooks/bauta-selector-hooks.mjs")

    const tempHooks = {}
    addBautaSelectorHooks(tempHooks)

    const selectorHook = tempHooks.BautaSelectorScreen
    if (selectorHook) {
      this.__mounted = selectorHook.mounted
      this.__updated = selectorHook.updated

      if (this.__mounted) {
        await this.__mounted.call(this)
      }
    }
  },

  async updated() {
    if (this.__updated) {
      await this.__updated.call(this)
    }
  },
})
