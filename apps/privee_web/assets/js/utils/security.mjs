import { Constants } from "./constants.mjs"
import { deleteObject, getObject, storeObject } from "./front-end-database.mjs"
import { arrayDataToString, stringToArrayData } from "./encryption-utils.mjs"

export const algorithm = "RSA-OAEP"

const modulusLength = 2048
const publicExponent = new Uint8Array([0x01, 0x00, 0x01])
const hash = "SHA-256"
const publicKeyFormat = "spki"
const privateKeyCacheInvalidationTime = 1_000 * 60 * 5

/**
 * Generates a public/private key pair.
 * @returns {Promise<CryptoKeyPair>} The pair of keys.
 */
export const generateNewKeyPair = () =>
  crypto.subtle.generateKey(
    {
      name: algorithm,
      modulusLength: modulusLength, // can be 1024, 2048, or 4096
      publicExponent: publicExponent,
      hash: hash, // can be "SHA-1", "SHA-256", "SHA-384", or "SHA-512"
    },
    true,
    ["encrypt", "decrypt"],
  )

/**
 * Convert the public key to string, to be subsequently stored in the database.
 * @param {CryptoKey} publicKey The generated public key.
 * @returns {Promise<string>} The public key in the string format.
 */
export const convertPublicKeyToString = async (publicKey) => {
  const exportedKey = await crypto.subtle.exportKey(publicKeyFormat, publicKey)
  const exportedKeyString = arrayDataToString(exportedKey)
  return btoa(exportedKeyString)
}

/**
 * Imports a public key in string format in a `CryptoKey` format, basically
 * converting it into a format that can be used to encrypt data.
 * @param {string} publicKey The public key in a string format.
 * @returns {Promise<CryptoKey>} The public key as a `CryptoKey` object.
 */
export const importStringPublicKey = (publicKey) => {
  const publicKeyBuffer = stringToArrayData(atob(publicKey))

  return crypto.subtle.importKey(
    publicKeyFormat,
    publicKeyBuffer,
    {
      name: algorithm,
      hash: {
        name: hash,
      },
    },
    true,
    ["encrypt"],
  )
}

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
 * @returns {void}
 */
export const handleSessionNamePrivateKeyRegistrationEvent = (event) => {
  // Adding a timeout to execute the function outside of the event loop, so that
  // it would not depend on the page refresh after the form submission.
  setTimeout(async () => await handleSessionNamePrivateKeyRegistrationEventInternal(event), 1)
}

/**
 * The event listener for the session name copy event triggered from the back end.
 * @param {import("./back-end-event-handlers.mjs").PhoenixSessionNameEvent} event The event sent from the back end.
 * @returns {Promise<void>}
 */
const handleSessionNamePrivateKeyRegistrationEventInternal = async (event) => {
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
}

var keyDictionary = new Map()

/**
 * Gets the private key for the session whose name is passed in input.
 * @param {string} sessionName The session name, that would be the key to retrieve the private key.
 * @returns {Promise<?CryptoKey>} The session private key.
 */
export const getPrivateKey = async (sessionName) => {
  const cache = keyDictionary[sessionName]

  if (cache && cache.lastUpdated > Date.now() - privateKeyCacheInvalidationTime) {
    return cache.key
  }

  const key = await getObject(Constants.dbName, Constants.tableName, sessionName)

  if (!key) {
    return null
  }

  keyDictionary[sessionName] = {
    lastUpdated: Date.now(),
    key,
  }

  return getPrivateKey(sessionName)
}

/**
 * These exports are for test purpose only.
 */
export const testExports = {
  arrayDataToString,
  stringToArrayData,
  handleSessionNamePrivateKeyRegistrationEventInternal,
}
