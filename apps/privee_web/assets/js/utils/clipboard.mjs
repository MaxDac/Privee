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
 */
export const addSessionNameCopyListener = () => {
  const copyButtons = getCopyButtons()

  copyButtons.forEach((button) => {
    button.removeEventListener("click", copyButtonHandler)
    button.addEventListener("click", copyButtonHandler)
  })
}

/**
 * Returns all the copy buttons in the page.
 * @returns {NodeListOf<HTMLButtonElement>} The copy buttons.
 */
const getCopyButtons = () => document.querySelectorAll("[data-session-name]")

/**
 * Produces a Handler to the click of the copy button click.
 */
function copyButtonHandler() {
  const sessionName = this.dataset.sessionName
  return copyTextToClipboard(sessionName)
}

/**
 * Tries to copy the text in input into the user clipboard through the browser API.
 * @param {string} text The text to copy into the clipboard.
 * @returns {Promise<void>} The result of the copy operation.
 */
const copyTextToClipboard = (text) => navigator.clipboard.writeText(text)

/**
 * The event listener for the session name copy event triggered from the back end.
 * It has been moved in this file to keep the `app.js` file clean.
 * @param {import("./back-end-event-handlers.mjs").PhoenixSessionNameEvent} event The event sent from the back end.
 */
export const handleSessionNameCopyToClipboardRegistrationEvent = (event) =>
  copySessionNameToClipboardBackEndEventHandler(event)
    .then(() => console.debug("Session name correctly copied to clipboard."))
    .catch((error) => console.debug("Failed to copy session name to clipboard.", error))
