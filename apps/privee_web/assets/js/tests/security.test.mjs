import test from "ava"
import {
  testExports,
  generateNewKeyPair,
  convertPublicKeyToString,
  importStringPublicKey,
  encryptMessage,
  decryptMessage,
} from "../utils/security.mjs"

const { stringToArrayData, arrayDataToString } = testExports

test("stringToArrayData should convert a string to an ArrayBuffer base64 representation", (t) => {
  const input = "Hello, World!"
  const expected = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33])
    .buffer
  const result = stringToArrayData(input)
  t.deepEqual(result, expected)
})

test("stringToArrayData should return an empty array if passed an empty string", (t) => {
  const input = ""
  const expected = new Uint8Array([]).buffer
  const result = stringToArrayData(input)
  t.deepEqual(result, expected)
})

test("stringToArrayData should return an empty array if passed null", (t) => {
  const input = null
  const expected = new Uint8Array([]).buffer
  const result = stringToArrayData(input)
  t.deepEqual(result, expected)
})

test("arrayDataToString should convert an ArrayBuffer to a string", (t) => {
  const input = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33]).buffer
  const expected = "Hello, World!"
  const result = arrayDataToString(input)
  t.deepEqual(result, expected)
})

test("arrayDataToString should convert an empty array to a string", (t) => {
  const input = new Uint8Array([]).buffer
  const expected = ""
  const result = arrayDataToString(input)
  t.deepEqual(result, expected)
})

test("arrayDataToString should convert null to an empty string", (t) => {
  const input = null
  const expected = ""
  const result = arrayDataToString(input)
  t.deepEqual(result, expected)
})

test("generateNewKeyPair should generate a new public/private key pair", async (t) => {
  const keyPair = await generateNewKeyPair()
  t.truthy(keyPair.publicKey)
  t.truthy(keyPair.privateKey)
})

test("convertPublicKeyToString should convert a public key to a string", async (t) => {
  const keyPair = await generateNewKeyPair()
  const publicKeyString = await convertPublicKeyToString(keyPair.publicKey)
  t.is(typeof publicKeyString, "string")
})

test("importStringPublicKey should import a public key in string format", async (t) => {
  const keyPair = await generateNewKeyPair()
  const publicKeyString = await convertPublicKeyToString(keyPair.publicKey)
  const importedPublicKey = await importStringPublicKey(publicKeyString)
  t.truthy(importedPublicKey)
})

test("encryptMessage should encrypt a message using a public key", async (t) => {
  const keyPair = await generateNewKeyPair()
  const message = "Hello, World!"
  const encryptedMessage = await encryptMessage(message, keyPair.publicKey)
  t.truthy(encryptedMessage)
})

test("decryptMessage should decrypt an encrypted message using a private key", async (t) => {
  const keyPair = await generateNewKeyPair()
  const message = "Hello, World!"
  const encryptedMessage = await encryptMessage(message, keyPair.publicKey)
  const decryptedMessage = await decryptMessage(encryptedMessage, keyPair.privateKey)
  t.is(decryptedMessage, message)
})
