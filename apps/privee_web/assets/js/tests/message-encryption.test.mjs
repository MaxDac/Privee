import { describe, it, expect } from "vitest"
import { encryptMessage, decryptMessage } from "../utils/message-encryption.mjs"
import { generateNewKeyPair } from "../utils/security.mjs"

describe("Message encryption", () => {
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

  it("encryptMessage and dercryptMessage should return an accented string", async () => {
    const keyPair = await generateNewKeyPair()
    const message = "Héllô, Wörld!"
    const encryptedMessage = await encryptMessage(message, keyPair.publicKey)
    const decryptedMessage = await decryptMessage(encryptedMessage, keyPair.privateKey)
    expect(decryptedMessage).toStrictEqual(message)
  })
})
