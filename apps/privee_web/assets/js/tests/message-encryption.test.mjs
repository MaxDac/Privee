import { test, describe, it, expect } from "vitest"
import { indexedDB } from "fake-indexeddb"
import { JSDOM } from "jsdom"
import { bindKeys, getPrivateKey, testExports } from "../utils/message-encryption.mjs"
import { getObject } from "../utils/front-end-database.mjs"
import { importStringPublicKey } from "../utils/security.mjs"
import { Constants } from "../utils/constants.mjs"

const html = "<input id='session-registration-public-key' type='hidden' />"

describe("bindKeys", () => {
  it("should bind public key generation to input field", async () => {
    const dom = new JSDOM(html)
    global.document = dom.window.document
    global.indexedDB = indexedDB

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
    global.document = dom.window.document
    global.indexedDB = indexedDB

    try {
      await bindKeys()
      expect.fail()
    } catch {
      /* Test passed */
    }
  })

  it("rebinds the keys if called twice", async () => {
    const dom = new JSDOM(html)
    global.document = dom.window.document
    global.indexedDB = indexedDB

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
  test(" should handle session name copy event", async () => {
    const dom = new JSDOM(html)
    global.indexedDB = indexedDB
    global.document = dom.window.document

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
  it("should return the private key for the given session name", async () => {
    const dom = new JSDOM(html)
    global.indexedDB = indexedDB
    global.document = dom.window.document

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
    global.indexedDB = indexedDB
    global.document = dom.window.document

    const privateKey = await getPrivateKey()

    expect(privateKey).toBeNull()
  })
})
