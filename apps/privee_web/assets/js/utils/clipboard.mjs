/**
  * @typedef {Object & Event} PhoenixEvent This type represents a custom Phoenix event.
  * @property {any} detail The event details
  */

/**
  * Copies the given text into the user clipboard.
  * @param {PhoenixEvent} [event] The event sent by the back-end.
  */
export const copyToClipboard = (event) => {
  const text = event.detail.session_name

  navigator.clipboard.writeText(text)
    .then(r => console.debug("Session name correctly copied to clipboard.", r))
    .catch(error => console.debug("Failed to copy session name to clipboard.", error))
}
