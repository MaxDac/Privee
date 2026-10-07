/**
 * Adds the hooks to the registration screen.
 *
 * Signal keys are not generated here: the session does not exist yet, and keys
 * are namespaced by session id. They are created and published by the first
 * authenticated page (selector or chat) through `SignalClient.ensureKeys`.
 * @param {any} Hooks The LiveView Hooks.
 */
export function addRegistrationHooks(Hooks) {
  Hooks.RegistrationScreen = {
    mounted() {},
  }
}
