const algorithm = "RSA-OAEP"
const modulusLength = 2048
const publicExponent = new Uint8Array([0x01, 0x00, 0x01])
const hash = "SHA-256"
const publicKeyFormat = "spki"

/**
 * Converts a string in base64 to an `ArrayBuffer.
 * @param {string} s The string to convert.
 * @returns {ArrayBuffer} The converted string.
 */
const stringToArrayData = (s) => {
  if (!s) {
    return new ArrayBuffer(0)
  }

  const bufferView = new Uint8Array(s.length)

  for (let i = 0; i < s.length; i++) {
    bufferView[i] = s.charCodeAt(i)
  }

  return bufferView.buffer
}

/**
 * Converts an array buffer into a base64 string.
 * @param {ArrayBuffer} a The array buffer.
 * @returns {string} The converted string.
 */
const arrayDataToString = (a) => String.fromCharCode.apply(null, new Uint8Array(a))

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
export const convertPublicKeyToString = (publicKey) =>
  crypto.subtle.exportKey(publicKeyFormat, publicKey).then(arrayDataToString).then(btoa)

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
 * Encrypts the message using the public key.
 * @param {string} message The message to encrypt.
 * @param {CryptoKey} publicKey The public key.
 * @returns {Promise<string>} The encrypted message.
 */
export const encryptMessage = (message, publicKey) => {
  const encoder = new TextEncoder()
  const encodedMessage = encoder.encode(message)

  return crypto.subtle
    .encrypt({ name: algorithm }, publicKey, encodedMessage)
    .then(arrayDataToString)
    .then(btoa)
}

/**
 * Decrypts the message using the private key.
 * @param {string} encryptedMessage The encrypted message.
 * @param {CryptoKey} privateKey The private key.
 * @returns {Promise<string>} The decrypted message.
 */
export const decryptMessage = (encryptedMessage, privateKey) =>
  crypto.subtle
    .decrypt({ name: algorithm }, privateKey, stringToArrayData(atob(encryptedMessage)))
    .then(arrayDataToString)

/**
 * These exports are for test purpose only.
 */
export const testExports = {
  arrayDataToString,
  stringToArrayData,
}
