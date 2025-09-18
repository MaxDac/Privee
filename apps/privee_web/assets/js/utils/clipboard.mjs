/**
 * Copies the given text into the user clipboard.
 * @param {import("./push-notifications.mjs").PhoenixEvent} [event] The event sent by the back-end.
 * @returns {Promise<void>} The result of the copy operation.
 */
export const copySessionNameToClipboardBackEndEventHandler = (event) => {
  const sessionName = event.detail.session_name
  return copyTextToClipboard(sessionName)
}

/**
 * Adds a listener to the copy buttons to copy the session name to the clipboard.
 * @param {import("../hooks/flash-hooks.mjs").PushFlash} pushFlash - The function to push events to the back end.
 */
export const addSessionNameCopyListener = (pushFlash) => {
  console.debug("Adding session name copy listener")
  const copyButtons = getCopyButtons()

  copyButtons.forEach((button) => {
    // Remove previous handler if present
    if (button._copyHandler) {
      button.removeEventListener("click", button._copyHandler);
    }
    // Create and store new handler
    const handler = createCopyButtonHandler(pushFlash);
    button._copyHandler = handler;
    button.addEventListener("click", handler);
  })
}

/**
 * Returns all the copy buttons in the page.
 * @returns {NodeListOf<HTMLButtonElement>} The copy buttons.
 */
const getCopyButtons = () => document.querySelectorAll("[data-session-name]")

/**
 * Produces a Handler to the click of the copy button click.
 * @param {import("../hooks/flash-hooks.mjs").PushFlash} pushFlash - The function to push events to the back end.
 */
const createCopyButtonHandler = (pushFlash) =>
  function () {
    const sessionName = this.dataset.sessionName
    const action = this.dataset.action

    if (action === "code") {
      console.debug("copying")
      return copyTextToClipboard(sessionName).then(() =>
        pushFlash("Info", "Session copied", "Info"),
      )
    } else {
      console.debug("copying -1")
      const sessionUrl = getSessionLoginMarkdownLink(sessionName)
      return copyTextToClipboard(sessionUrl).then(() => pushFlash("Info", "Url copied", "Info"))
    }
  }

/**
 * Tries to copy the text in input into the user clipboard through the browser API.
 * @param {string} text The text to copy into the clipboard.
 * @returns {Promise<void>} The result of the copy operation.
 */
const copyTextToClipboard = (text) => navigator.clipboard.writeText(text)

/**
 * Generates a session login URL for cross-platform compatibility.
 * Returns a plain URL that works optimally across different platforms:
 * - Browsers: pastes as clean address
 * - Text engines: shows just the link
 * - Teams/Word: auto-detects as clickable hyperlink
 *
 * @param {string} code - The session code to include in the share URL.
 * @returns {string} A plain URL for the session share.
 *
 * Example:
 *   getSessionLoginMarkdownLink('abc123', 'Login Link')
 *   // Returns: https://current-host/share/abc123
 */
const getSessionLoginMarkdownLink = (code) => {
  const host = window.location.origin
  const url = `${host}/share/${encodeURIComponent(code)}`
  return url
}

/**
 * The event listener for the session name copy event triggered from the back end.
 * It has been moved in this file to keep the `app.js` file clean.
 * @param {import("./back-end-event-handlers.mjs").PhoenixSessionNameEvent} event The event sent from the back end.
 */
export const handleSessionNameCopyToClipboardRegistrationEvent = (event) =>
  copySessionNameToClipboardBackEndEventHandler(event)
    .then(() => console.debug("Session name correctly copied to clipboard."))
    .catch((error) => console.debug("Failed to copy session name to clipboard.", error))

/**
 * These exports are for test purpose only.
 */
export const testExports = {
  getSessionLoginMarkdownLink,
  getCopyButtons,
  createCopyButtonHandler,
}
