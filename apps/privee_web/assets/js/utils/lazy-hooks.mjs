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
  /** @this {Record<string, any>} */
  async mounted() {
    // Dynamic import - only loads when this hook is used
    const { addChatHooks } = await import("../hooks/chat-hooks.mjs")

    // Create temporary hooks object
    /** @type {Record<string, any>} */
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

  /** @this {Record<string, any>} */
  async updated() {
    if (this.__updated) {
      await this.__updated.call(this)
    }
  },

  /** @this {Record<string, any>} */
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

    /** @type {Record<string, any>} */
    const tempHooks = {}
    addRegistrationHooks(tempHooks)

    const regScreenHook = tempHooks.RegistrationScreen
    if (regScreenHook && regScreenHook.mounted) {
      await regScreenHook.mounted.call(this)
    }
  },
})

/**
 * Creates a lazy-loaded wrapper for the PriveeSelectorScreen hook.
 * Only loads selector functionality when the hook is mounted on a page.
 * @returns {object} The lazy-loaded PriveeSelectorScreen hook
 */
export const createLazyPriveeSelectorScreenHook = () => ({
  /** @this {Record<string, any>} */
  async mounted() {
    const { addPriveeSelectorHooks } = await import("../hooks/privee-selector-hooks.mjs")

    /** @type {Record<string, any>} */
    const tempHooks = {}
    addPriveeSelectorHooks(tempHooks)

    const selectorHook = tempHooks.PriveeSelectorScreen
    if (selectorHook) {
      this.__mounted = selectorHook.mounted
      this.__updated = selectorHook.updated

      if (this.__mounted) {
        await this.__mounted.call(this)
      }
    }
  },

  /** @this {Record<string, any>} */
  async updated() {
    if (this.__updated) {
      await this.__updated.call(this)
    }
  },
})
