import { Constants } from "./constants.mjs"
import { deleteObject, getObject, storeObject } from "./front-end-database.mjs"
import { convertPublicKeyToString, generateNewKeyPair } from "./security.mjs"

/**
 * Binds the public key generation to the input field, and save the correspondent
 * private key in the IndexedDB.
 */
export const bindKeys = async () => {
  const inputSelector = "#session-registration-public-key"
  /** @type {HTMLInputElement} */ const hiddenInput = document.querySelector(inputSelector)

  if (!hiddenInput) {
    throw new Error("The input field is not available.")
  }

  try {
    const { publicKey, privateKey } = await generateNewKeyPair()
    await storeObject(
      Constants.dbName,
      Constants.tableName,
      Constants.privateKeyTempKey,
      privateKey,
    )
    const publicKeyAsString = await convertPublicKeyToString(publicKey)

    hiddenInput.value = publicKeyAsString

    console.debug("The public key has been populated.")
  } catch (e) {
    console.error("An error occourerd while generating the key pair.", e)
  }
}

/**
 * The event listener for the session name copy event triggered from the back end.
 * It has been moved in this file to keep the `app.js` file clean.
 * @param {import("./back-end-event-handlers.mjs").PhoenixSessionNameEvent} event The event sent from the back end.
 * @returns {Promise<void>} A promise that resolves when the private key has been stored.
 */
export const handleSessionNamePrivateKeyRegistrationEvent = async (event) => {
  setTimeout(async () => {
    const sessionName = event.detail.session_name

    try {
      const privateKey = await getObject(
        Constants.dbName,
        Constants.tableName,
        Constants.privateKeyTempKey,
      )
      await storeObject(Constants.dbName, Constants.tableName, sessionName, privateKey)
      await deleteObject(Constants.dbName, Constants.tableName, Constants.privateKeyTempKey)
      return console.debug("The private key has been stored with the right key.")
    } catch {
      return console.error("An error occurred while storing the private key.")
    }
  }, 1)
}
