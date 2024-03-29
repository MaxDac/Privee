import { describe, it, expect } from "vitest"
import {
  testExports,
  generateNewKeyPair,
  convertPublicKeyToString,
  importStringPublicKey,
  encryptMessage,
  decryptMessage,
} from "../utils/security.mjs"

const { stringToArrayData, arrayDataToString } = testExports

describe("stringToArrayData", () => {
  it("should convert a string to an ArrayBuffer base64 representation", () => {
    const input = "Hello, World!"
    const expected = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33])
      .buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })

  it("should return an empty array if passed an empty string", () => {
    const input = ""
    const expected = new Uint8Array([]).buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })

  it("should return an empty array if passed null", () => {
    const input = null
    const expected = new Uint8Array([]).buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })
})

describe("arrayDataToString", () => {
  it("should convert an ArrayBuffer to a string", () => {
    const input = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33])
      .buffer
    const expected = "Hello, World!"
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })

  it("should convert an empty array to a string", () => {
    const input = new Uint8Array([]).buffer
    const expected = ""
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })

  it("should convert null to an empty string", () => {
    const input = null
    const expected = ""
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })
})

describe("Key operations", () => {
  it("generateNewKeyPair should generate a new public/private key pair", async () => {
    const keyPair = await generateNewKeyPair()
    expect(keyPair.publicKey).toBeTruthy()
    expect(keyPair.privateKey).toBeTruthy()
  })

  it("convertPublicKeyToString should convert a public key to a string", async () => {
    const keyPair = await generateNewKeyPair()
    const publicKeyString = await convertPublicKeyToString(keyPair.publicKey)
    expect(publicKeyString).toBeTypeOf("string")
  })

  it("importStringPublicKey should import a public key in string format", async () => {
    const keyPair = await generateNewKeyPair()
    const publicKeyString = await convertPublicKeyToString(keyPair.publicKey)
    const importedPublicKey = await importStringPublicKey(publicKeyString)
    expect(importedPublicKey).toBeTruthy()
  })

  it("encryptMessage should encrypt a message using a public key", async () => {
    const keyPair = await generateNewKeyPair()
    const message = "Hello, World!"
    const encryptedMessage = await encryptMessage(message, keyPair.publicKey)
    expect(encryptedMessage).toBeTruthy()
  })

  it("decryptMessage should decrypt an encrypted message using a private key", async () => {
    const keyPair = await generateNewKeyPair()
    const message = "Hello, World!"
    const encryptedMessage = await encryptMessage(message, keyPair.publicKey)
    const decryptedMessage = await decryptMessage(encryptedMessage, keyPair.privateKey)
    expect(decryptedMessage).toBe(message)
  })
})
