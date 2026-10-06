import { arrayDataToString, stringToArrayData } from "./encryption-utils.mjs"
import { algorithm } from "./security.mjs"

/**
 * Encrypts the message using the public key.
 * @param {string} message The message to encrypt.
 * @param {CryptoKey} publicKey The public key.
 * @returns {Promise<string>} The encrypted message.
 */
export const encryptMessage = async (message, publicKey) => {
  const encoder = new TextEncoder()
  const encodedMessage = encoder.encode(message)

  const encryptedBuffer = await crypto.subtle.encrypt(
    { name: algorithm },
    publicKey,
    encodedMessage,
  )
  const encryptedString = arrayDataToString(encryptedBuffer)
  return btoa(encryptedString)
}

/**
 * Decrypts the message using the private key.
 * @param {string} encryptedMessage The encrypted message.
 * @param {CryptoKey} privateKey The private key.
 * @returns {Promise<string>} The decrypted message.
 */
export const decryptMessage = async (encryptedMessage, privateKey) => {
  const decoder = new TextDecoder()
  const encryptedMessageBuffer = stringToArrayData(atob(encryptedMessage))
  const algorithmIdentifier = { name: algorithm }
  const decryptedMessageBuffer = await crypto.subtle.decrypt(
    algorithmIdentifier,
    privateKey,
    encryptedMessageBuffer,
  )

  return decoder.decode(decryptedMessageBuffer)
}
