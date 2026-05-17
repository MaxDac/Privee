import { handleSessionNameCopyToClipboardRegistrationEvent } from "./clipboard.mjs"
import { getPendingPreKeyBundle } from "../hooks/registration-hooks.mjs"

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
 * @param {Function} [pushEvent] Optional LiveView pushEvent for sending prekey bundle
 */
export const handleSessionNameRegistrationEvent = (event, pushEvent) => {
  handleSessionNameCopyToClipboardRegistrationEvent(event)
  uploadPreKeyBundle(pushEvent)
}

/**
 * Uploads the pending prekey bundle to the server.
 * @param {Function} [pushEvent] - LiveView pushEvent function
 */
const uploadPreKeyBundle = (pushEvent) => {
  if (!pushEvent) return

  setTimeout(() => {
    const bundle = getPendingPreKeyBundle()
    if (bundle) {
      pushEvent("register_prekeys", {
        identity_key: bundle.identityKey,
        registration_id: bundle.registrationId,
        signed_prekey: {
          key_id: bundle.signedPreKey.keyId,
          public_key: bundle.signedPreKey.publicKey,
          signature: bundle.signedPreKey.signature,
        },
        one_time_prekeys: bundle.oneTimePreKeys.map((pk) => ({
          key_id: pk.keyId,
          public_key: pk.publicKey,
        })),
      })
    }
  }, 1)
}
