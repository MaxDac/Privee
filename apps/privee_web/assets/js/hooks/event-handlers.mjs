import topbar from "../../vendor/topbar"
import { handleSendingPublicKey } from "../utils/chat.mjs"
import { handleSessionNameCopyToClipboardRegistrationEvent } from "../utils/clipboard.mjs"
import { addToggleDarkModeHandling, setStartupTheme } from "../utils/dark-mode-switcher.mjs"
import { handleSessionNamePrivateKeyRegistrationEvent } from "../utils/security.mjs"
import { askNotificationPermission, pushBackEndNotification } from "../utils/push-notifications.mjs"

/**
 * Adds the event handlers to the front end, to handle events fired from the back-end.
 * @returns {void}
 */
export const addBackEndEventHandlers = () => {
  // Page loading events
  window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
  window.addEventListener("phx:page-loading-stop", (_info) => {
    topbar.hide()

    // Adding this because for some reason it gets reset at page load.
    setStartupTheme()
  })

  // Adds the dark mode toggle handling
  document.addEventListener("DOMContentLoaded", addToggleDarkModeHandling)

  // Asking for notification permission to the browser
  askNotificationPermission().then(console.debug).catch(console.error)

  // Push notifications
  window.addEventListener("phx:trigger_notification", pushBackEndNotification)

  // Post registration handlers
  window.addEventListener("phx:handle_new_session_registration", addNewSessionRegistrationHandler)

  // Adding the crypto keys handling for the chat
  window.addEventListener("phx:sending_keys", handleSendingPublicKey)

  // Close session dropdown when any menu item is clicked
  document.addEventListener("click", (event) => {
    const sessionMenu = document.getElementById("session-menu")

    if (!sessionMenu) return

    // Check if the clicked element is inside the session menu
    const target = event.target

    if (!(target instanceof Node)) return

    const isSessionMenuClick = sessionMenu.contains(target)

    if (!isSessionMenuClick) return

    // Check if the clicked element is a clickable menu item
    const clickableSelectors = [
      "#copy-session-code-btn",
      "#copy-session-url-btn",
      "a[href='/sessions/log_out']", // Sign out link
    ]

    // Check if target is an Element and has closest method
    const isClickableItem =
      target instanceof Element && clickableSelectors.some((selector) => target.closest(selector))

    if (isClickableItem) {
      // Hide the dropdown by triggering the toggle button
      const dropdownToggle = document.querySelector("[data-dropdown-toggle='session-menu']")
      if (dropdownToggle instanceof HTMLElement && !sessionMenu.classList.contains("hidden")) {
        dropdownToggle.click()
      }
    }
  })
}

/**
 * Handles the event of the registration of new sessions.
 * @param {Event} event The event that triggered the registration.
 * @returns {Promise<void>} A promise that resolves when the event is handled.
 */
const addNewSessionRegistrationHandler = async (event) => {
  await handleSessionNameCopyToClipboardRegistrationEvent(event)
  await handleSessionNamePrivateKeyRegistrationEvent(event)
}
