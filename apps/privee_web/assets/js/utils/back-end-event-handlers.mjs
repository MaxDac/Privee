import { handleSessionNameCopyToClipboardRegistrationEvent } from "./clipboard.mjs"

/**
 * @typedef {object} PhoenixSessionNameEventDetail This type represents a custom Phoenix event.
 * @property {string} session_name The logged user session name.
 */

/**
 * @typedef {{detail: PhoenixSessionNameEventDetail} & Event} PhoenixSessionNameEvent This type represents a custom Phoenix event.
 */

/**
 * Handles the session name registration event, triggering and handling all the related events.
 * @param {PhoenixSessionNameEvent} event The back end event payload.
 */
export const handleSessionNameRegistrationEvent = (event) => {
  handleSessionNameCopyToClipboardRegistrationEvent(event)
}
