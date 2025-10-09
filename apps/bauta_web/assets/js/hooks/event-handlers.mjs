import topbar from "../../vendor/topbar"
import { handleSessionNameCopyToClipboardRegistrationEvent } from "../utils/clipboard.mjs"
import { addToggleDarkModeHandling, setStartupTheme } from "../utils/dark-mode-switcher.mjs"
import { askNotificationPermission, pushBackEndNotification } from "../utils/push-notifications.mjs"

// Cache for lazy-loaded handlers to avoid re-importing on every event
let cachedHandleSendingPublicKey = null
let cachedHandleSessionNamePrivateKeyRegistrationEvent = null

/**
 * Lazy-loads and caches the chat utilities.
 * @returns {Promise<Function>} The handleSendingPublicKey function.
 */
const getChatHandler = async () => {
  if (!cachedHandleSendingPublicKey) {
    const chatModule = await import("../utils/chat.mjs")
    cachedHandleSendingPublicKey = chatModule.handleSendingPublicKey
  }
  return cachedHandleSendingPublicKey
}

/**
 * Lazy-loads and caches the security utilities.
 * @returns {Promise<Function>} The handleSessionNamePrivateKeyRegistrationEvent function.
 */
const getSecurityHandler = async () => {
  if (!cachedHandleSessionNamePrivateKeyRegistrationEvent) {
    const securityModule = await import("../utils/security.mjs")
    cachedHandleSessionNamePrivateKeyRegistrationEvent =
      securityModule.handleSessionNamePrivateKeyRegistrationEvent
  }
  return cachedHandleSessionNamePrivateKeyRegistrationEvent
}

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

  // Post registration handlers - lazy-loaded with caching
  window.addEventListener("phx:handle_new_session_registration", async (event) => {
    const handleSessionNamePrivateKeyRegistrationEvent = await getSecurityHandler()
    await handleSessionNameCopyToClipboardRegistrationEvent(event)
    await handleSessionNamePrivateKeyRegistrationEvent(event)
  })

  // Adding the crypto keys handling for the chat - lazy-loaded with caching
  window.addEventListener("phx:sending_keys", async (event) => {
    const handleSendingPublicKey = await getChatHandler()
    handleSendingPublicKey(event)
  })

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
      // Close the dropdown by removing the "open" attribute from details element
      const dropdownDetails = sessionMenu.closest("details")
      if (dropdownDetails instanceof HTMLDetailsElement && dropdownDetails.open) {
        dropdownDetails.open = false
      }
    }
  })
}
