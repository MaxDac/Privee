/**
 * Lazy loading utilities for Phoenix LiveView hooks.
 * Page-specific hooks (and their dependencies, such as the Signal library) are
 * only loaded when the hook is mounted.
 */

/**
 * Creates a hook that imports its implementation on mount and forwards the
 * lifecycle callbacks to it. `destroyed` may run before the import resolves:
 * the implementation is then never mounted.
 * @param {() => Promise<any>} load Dynamic import of the hook module.
 * @param {string} registrar Name of the exported `add*Hooks(Hooks)` function.
 * @param {string} name Hook name.
 * @returns {object} The lazy hook.
 */
export const createLazyHook = (load, registrar, name) => ({
  /** @this {Record<string, any>} */
  async mounted() {
    const module = await load()
    /** @type {Record<string, any>} */
    const hooks = {}
    module[registrar](hooks)
    this.__impl = hooks[name] || {}
    if (this.__destroyed) return
    await this.__impl.mounted?.call(this)
  },

  /** @this {Record<string, any>} */
  updated() {
    return this.__impl?.updated?.call(this)
  },

  /** @this {Record<string, any>} */
  destroyed() {
    this.__destroyed = true
    return this.__impl?.destroyed?.call(this)
  },
})

export const createLazyChatScreenHook = () =>
  createLazyHook(() => import("../hooks/chat-hooks.mjs"), "addChatHooks", "ChatScreen")

export const createLazyRegistrationScreenHook = () =>
  createLazyHook(
    () => import("../hooks/registration-hooks.mjs"),
    "addRegistrationHooks",
    "RegistrationScreen",
  )

export const createLazyPriveeSelectorScreenHook = () =>
  createLazyHook(
    () => import("../hooks/privee-selector-hooks.mjs"),
    "addPriveeSelectorHooks",
    "PriveeSelectorScreen",
  )
