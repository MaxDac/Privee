import { bindKeys } from "../utils/message-encryption.mjs"

/**
 * Adds the hooks to the registration screen.
 * @param {any} Hooks The LiveView Hooks.
 */
export function addRegistrationHooks(Hooks) {
  Hooks.RegistrationScreen = {
    mounted() {
      console.debug("Adding hooks to the registration screen.")
      bindKeys()
    },
  }
}
