import { describe, it, expect } from "vitest"
import { JSDOM } from "jsdom"
import { testExports, handleSendingPrivateKey, handleChatInput } from "../utils/chat.mjs"
import { convertPublicKeyToString, decryptMessage, generateNewKeyPair } from "../utils/security.mjs"

const html = `
  <form id="chat-form">
    <input type="hidden" id="text-from" />
    <input type="hidden" id="text-to" />
    <input type-"text" id="chat-text" />
  </form>
`

describe("handleSendingPrivateKey", () => {
  it("should return an error when the keys are not present", async () => {
    const event = {
      detail: {},
    }

    try {
      await handleSendingPrivateKey(event)
      expect.fail("It should have thrown an exception")
    } catch (_e) {
      /* test passing */
    }
  })

  it("handleSendingPrivateKey should store the public key", async () => {
    const { publicKey: currentPublicKey } = await generateNewKeyPair()
    const { publicKey: selectedPublicKey } = await generateNewKeyPair()
    const currentPublicKeyString = await convertPublicKeyToString(currentPublicKey)
    const selectedPublicKeyString = await convertPublicKeyToString(selectedPublicKey)

    const event = {
      detail: {
        current: currentPublicKeyString,
        selected: selectedPublicKeyString,
      },
    }

    await handleSendingPrivateKey(event)

    const currentPublicKeyFromModule = testExports.getCurrentPublicKey()
    const selectedPublicKeyFromModule = testExports.getSelectedPublicKey()

    expect(currentPublicKeyFromModule).toBeTruthy()
    expect(currentPublicKeyFromModule).toBeTruthy()
    expect(selectedPublicKeyFromModule).toBeTruthy()

    expect(await convertPublicKeyToString(currentPublicKeyFromModule)).toBe(currentPublicKeyString)
    expect(await convertPublicKeyToString(selectedPublicKeyFromModule)).toBe(selectedPublicKeyString)
  })
})

describe("handleChatInput", () => {
  it(" should encrypt and set the values of hidden inputs", async () => {
    const { publicKey: currentPublicKey, privateKey: currentPrivateKey } = await generateNewKeyPair()

    const { publicKey: selectedPublicKey, privateKey: selectedPrivateKey } =
      await generateNewKeyPair()

    const currentPublicKeyString = await convertPublicKeyToString(currentPublicKey)
    const selectedPublicKeyString = await convertPublicKeyToString(selectedPublicKey)

    const dom = new JSDOM(html)
    global.document = dom.window.document
    global.Event = dom.window.Event
    global.KeyboardEvent = dom.window.KeyboardEvent

    // Simulating the event from the back end which sends the public keys
    const publicKeysSendingEvent = {
      detail: {
        current: currentPublicKeyString,
        selected: selectedPublicKeyString,
      },
    }

    await handleSendingPrivateKey(publicKeysSendingEvent)

    // @ts-ignore
    /** @type {HTMLFormElement} */ const form = document.querySelector("#chat-form")
    /** @type {HTMLInputElement} */ const textbox = document.querySelector("#chat-text")
    /** @type {HTMLInputElement} */ const hiddenTextFrom = document.querySelector("#text-from")
    /** @type {HTMLInputElement} */ const hiddenTextTo = document.querySelector("#text-to")

    // Simulating filling the input with a message
    const inputText = "Hello, world!"

    textbox.value = inputText

    // Workaround for the event listener to be added and fired from the form.
    // This function will later be bound to the `Promise` that will resolve the test.
    let testResolve = null

    // Adding a submit event listener for the form to check the values of the hidden inputs
    form.addEventListener("submit", async (e) => {
      e.preventDefault()

      expect(hiddenTextFrom.value).toBe("")
      expect(hiddenTextTo.value).toBe("")

      const fromMessage = await decryptMessage(hiddenTextFrom.value, currentPrivateKey)
      const toMessage = await decryptMessage(hiddenTextTo.value, selectedPrivateKey)

      expect(fromMessage).toBe(inputText)
      expect(toMessage).toBe(inputText)

      expect(textbox.value).toBe("")

      testResolve()
    })

    await handleChatInput(new KeyboardEvent("keypress", { key: "Enter" }))

    await new Promise((resolve) => {
      // Binding the resolve function to the testResolve variable.
      // This will be resolved when the submit event is fired and handled by the
      // test event listener.
      testResolve = resolve
    })
  })

  it("handleChatInput should do nothing when the chat input is empty", async () => {
    const { publicKey: currentPublicKey } = await generateNewKeyPair()

    const { publicKey: selectedPublicKey } = await generateNewKeyPair()

    const currentPublicKeyString = await convertPublicKeyToString(currentPublicKey)
    const selectedPublicKeyString = await convertPublicKeyToString(selectedPublicKey)

    const dom = new JSDOM(html)
    global.document = dom.window.document
    global.Event = dom.window.Event
    global.KeyboardEvent = dom.window.KeyboardEvent

    // Simulating the event from the back end which sends the public keys
    const publicKeysSendingEvent = {
      detail: {
        current: currentPublicKeyString,
        selected: selectedPublicKeyString,
      },
    }

    await handleSendingPrivateKey(publicKeysSendingEvent)

    // @ts-ignore
    /** @type {HTMLInputElement} */ const textbox = document.querySelector("#chat-text")
    /** @type {HTMLInputElement} */ const hiddenTextFrom = document.querySelector("#text-from")
    /** @type {HTMLInputElement} */ const hiddenTextTo = document.querySelector("#text-to")

    textbox.value = ""

    await handleChatInput(new KeyboardEvent("submit"))

    expect(hiddenTextFrom.value).toBe("")
    expect(hiddenTextTo.value).toBe("")
  })
})
