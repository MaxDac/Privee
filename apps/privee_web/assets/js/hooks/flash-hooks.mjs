/**
 * A function that pushes a notification/event to the back end.
 *
 * @callback PushFlash
 * @param {"Info"|"Warning"|"Error"} kind - The kind of notification.
 * @param {string} message - The message to push.
 * @param {string?} [title] - Optional title for the notification.
 * @returns {Promise<void>} Resolves when the push operation completes.
 */

/**
 * A function that pushes an event to the back end.
 *
 * @callback PushEvent
 * @param {string} eventName - The even name.
 * @param {object} attrs - The event attribute.
 * @param {(reply: any) => void} callback - The event callback.
 * @returns {void}
 */

/**
 * Simple JavaScript flash message utilities
 *
 * These functions allow triggering server-side flash messages from JavaScript.
 * The flash messages will appear in the existing flash_group component.
 */

const flashEventName = "js_flash"

/**
 * Push a flash message to the server that will appear in the regular flash container
 * @param {PushEvent} pushEvent - The push event from the hook.
 * @returns {PushFlash} The function which triggers the flash on the back end.
 */
export const pushFlash = (pushEvent) => (kind, message, title = null) =>
  new Promise((res, _rej) => {
    pushEvent(flashEventName, { kind, message, title }, (reply) => {
      res(reply)
    })
  })

/**
 * Adds a hook that automatically hides the flash message after 5 seconds.
 * @param {any} Hooks LiveView Hooks
 */
export const addFlashAutoHideHook = (Hooks) => {
  Hooks.FlashAutoHide = {
    mounted() {
      setTimeout(() => {
        this.el.style.display = "none"
      }, 5_000)
    },
  }
}
