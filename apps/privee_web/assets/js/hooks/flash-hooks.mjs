/**
 * Simple JavaScript flash message utilities
 *
 * These functions allow triggering server-side flash messages from JavaScript.
 * The flash messages will appear in the existing flash_group component.
 */

/**
 * Push a flash message to the server that will appear in the regular flash container
 * @param {"info" | "error" | "warning"} kind - The flash message type: 'info', 'error', or 'warning'
 * @param {string} message - The flash message content
 * @param {string} [title] - Optional title for the flash message
 */
export const pushFlash = (kind, message, title) => {
  console.debug("Pushing flash")
  // @ts-ignore
  if (window.liveSocket) {
    // Find any LiveView element to push the event to
    const liveElements = document.querySelectorAll("[data-phx-main]")
    if (liveElements.length > 0) {
      // Get the LiveView from the element and push the event
      const liveElement = liveElements[0]
      // @ts-ignore
      console.debug("LiveSocket object:", window.liveSocket)
      console.debug("Found LiveView element:", liveElement)
      // @ts-ignore
      const liveView = window.liveSocket.getViewByEl(liveElement)
      console.debug("Retrieved LiveView:", liveView)
      if (liveView) {
        liveView.pushEvent("js_flash", {
          attributes: {
            kind: kind,
            message: message,
            title: title,
          },
        })
      } else {
        console.warn("LiveView not found on element. Flash message not sent:", {
          kind,
          message,
          title,
        })
      }
    } else {
      console.warn("No LiveView found. Flash message not sent:", { kind, message, title })
    }
  } else {
    console.warn("LiveSocket not available. Flash message not sent:", { kind, message, title })
  }
}
