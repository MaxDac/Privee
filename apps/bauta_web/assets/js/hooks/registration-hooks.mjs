import { bindKeys } from "../utils/security.mjs"

/**
 * Adds the hooks to the registration screen.
 * @param {any} Hooks The LiveView Hooks.
 */
export function addRegistrationHooks(Hooks) {
  Hooks.RegistrationScreen = {
    mounted() {
      bindKeys()
    },
  }
}
