/**
  * Copies the given text into the user clipboard.
  * @param {string} [text] The event sent by the back-end.
  */
const copyToClipboard = text => {
  navigator.clipboard.writeText(text)
    .then(r => console.debug("Session name correctly copied to clipboard.", text, r))
    .catch(error => console.debug("Failed to copy session name to clipboard.", error))
}

/**
 * Returns all the copy buttons in the page.
 * @returns {NodeListOf<HTMLButtonElement>} The copy buttons.
 */
const getCopyButtons = () => document.querySelectorAll("[data-session-name]")

/**
 * Adds a listener to the copy buttons to copy the session name to the clipboard.
 */
export const addSessionNameCopyListener = () => {
  const copyButtons = getCopyButtons()

  copyButtons.forEach(button => {
    button.removeEventListener("click", copyButtonHandler)
    button.addEventListener("click", copyButtonHandler)
  })
}


/**
  * @typedef {Object & Event} PhoenixEvent This type represents a custom Phoenix event.
  * @property {any} detail The event details
  */

/**
  * Copies the given text into the user clipboard.
  * @param {PhoenixEvent} [event] The event sent by the back-end.
  */
export const copyToClipboardBackEndEventHandler = event => {
  const sessionName = event.detail.session_name
  copyToClipboard(sessionName)
}

/**
 * @typedef {Object & Event} ButtonEvent This type represents a custom button event.
 * @property {HTMLButtonElement} target The button that was clicked.
 */

/**
 * Produces a Handler to the click of the copy button click.
 */
function copyButtonHandler() {
  const sessionName = this.dataset.sessionName
  copyToClipboard(sessionName)
}