import { describe, it, expect, vi, afterEach } from "vitest"
import { indexedDB } from "fake-indexeddb"
import { JSDOM } from "jsdom"
import {
  testExports,
  generateNewKeyPair,
  convertPublicKeyToString,
  importStringPublicKey,
  getPrivateKey,
  bindKeys,
} from "../utils/security.mjs"
import { getObject } from "../utils/front-end-database.mjs"
import { Constants } from "../utils/constants.mjs"

const html = "<input id='session-registration-public-key' type='hidden' />"

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
})

describe("bindKeys", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("should bind public key generation to input field", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("indexedDB", indexedDB)

    await bindKeys()

    /** @type{HTMLInputElement} */ const hiddenInput = document.querySelector(
      "#session-registration-public-key",
    )

    const hiddenInputValue = hiddenInput.value

    expect(hiddenInputValue.length).toBeGreaterThan(0)

    const publicKey = importStringPublicKey(hiddenInputValue)
    const privateKey = getObject(Constants.dbName, Constants.tableName, "private_key")

    expect(publicKey).toBeTypeOf("object")
    expect(publicKey).toBeTruthy()
    expect(privateKey).toBeTypeOf("object")
    expect(privateKey).toBeTruthy()
  })

  it("does not work if the hidden input is not present in the DOM", async () => {
    const dom = new JSDOM()
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("indexedDB", indexedDB)

    try {
      await bindKeys()
      expect.fail()
    } catch {
      /* Test passed */
    }
  })

  it("rebinds the keys if called twice", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("indexedDB", indexedDB)

    await bindKeys()
    await bindKeys()

    /** @type{HTMLInputElement} */ const hiddenInput = document.querySelector(
      "#session-registration-public-key",
    )

    const hiddenInputValue = hiddenInput.value

    expect(hiddenInputValue.length).toBeGreaterThan(0)

    const publicKey = importStringPublicKey(hiddenInputValue)
    const privateKey = getObject(Constants.dbName, Constants.tableName, "private_key")

    expect(publicKey).toBeTypeOf("object")
    expect(publicKey).toBeTruthy()
    expect(privateKey).toBeTypeOf("object")
    expect(privateKey).toBeTruthy()
  })
})

describe("handleSessionNamePrivateKeyRegistrationEvent", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it(" should handle session name copy event", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("indexedDB", indexedDB)
    vi.stubGlobal("document", dom.window.document)

    await bindKeys()

    const event = {
      detail: {
        sessionName: "test-session-name",
      },
    }

    await testExports.handleSessionNamePrivateKeyRegistrationEventInternal(event)

    const privateKey = getObject(Constants.dbName, Constants.tableName, "test-session-name")

    expect(privateKey).toBeTypeOf("object")
    expect(privateKey).toBeTruthy()
  })
})

describe("getPrivateKey", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("should return the private key for the given session name", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("indexedDB", indexedDB)
    vi.stubGlobal("document", dom.window.document)

    await bindKeys()

    await testExports.handleSessionNamePrivateKeyRegistrationEventInternal({
      detail: {
        session_name: "test-session-name",
      },
    })

    const privateKey = await getPrivateKey("test-session-name")

    expect(privateKey).toBeTypeOf("object")
    expect(privateKey).toBeTruthy()
  })

  it("should return null if the private key is not found", async () => {
    const dom = new JSDOM()
    vi.stubGlobal("indexedDB", indexedDB)
    vi.stubGlobal("document", dom.window.document)

    const privateKey = await getPrivateKey()

    expect(privateKey).toBeNull()
  })
})
