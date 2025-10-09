import { handleSessionNameCopyToClipboardRegistrationEvent } from "./clipboard.mjs"
import { handleSessionNamePrivateKeyRegistrationEvent } from "./security.mjs"

/**
 * @typedef {object} PhoenixSessionNameEventDetail This type represents a custom Phoenix event.
 * @property {string} session_name The logged user session name.
 */

/**
 * @typedef {object & Event} PhoenixSessionNameEvent This type represents a custom Phoenix event.
 * @property {PhoenixSessionNameEventDetail} detail The event details
 */

/**
 * Handles the session name registration event, triggering and handling all the related events.
 * @param {PhoenixSessionNameEvent} event The back end event payload.
 */
export const handleSessionNameRegistrationEvent = (event) => {
  handleSessionNameCopyToClipboardRegistrationEvent(event)
  handleSessionNamePrivateKeyRegistrationEvent(event)
}
