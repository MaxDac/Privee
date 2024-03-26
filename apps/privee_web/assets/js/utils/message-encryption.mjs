import { deleteObject, getObject, storeObject } from "./front-end-database.mjs"
import { convertPublicKeyToString, generateNewKeyPair } from "./security.mjs"

/**
 * Binds the public key generation to the input field, and save the correspondent
 * private key in the IndexedDB.
 */
export const bindKeys = async () => {
  const inputSelector = "#session-registration-public-key"
  /** @type {HTMLInputElement} */ const hiddenInput = document.querySelector(inputSelector) 

  if (hiddenInput) {
    return generateNewKeyPair()
      .then(({publicKey, privateKey}) =>
        // Storing the key
        storeObject("private_key", privateKey)
          .then(() => publicKey)
      )
      .then(convertPublicKeyToString)
      .then(publicKey =>
        // Populating the input
        hiddenInput.value = publicKey
      )
      .then(() => console.debug("The public key has been populated."))
      .catch(e => console.error("An error occourerd while generating the key pair.", e))
  }

  return Promise.reject("The input field is not available.")
}

/**
  * The event listener for the session name copy event triggered from the back end.
  * It has been moved in this file to keep the `app.js` file clean.
  * @param {import("./back-end-event-handlers.mjs").PhoenixSessionNameEvent} event The event sent from the back end.
  */
export const handleSessionNamePrivateKeyRegistrationEvent = event => {
  const sessionName = event.detail.sessionName
  getObject("private_key")
    .then(privateKey => storeObject(sessionName, privateKey))
    .then(() => deleteObject("private_key"))
    .then(() => console.debug("The private key has been stored with the right key."))
    .catch(() => console.error("An error occurred while storing the private key."))
}
