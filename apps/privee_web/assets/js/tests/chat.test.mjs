import { describe, it, expect } from "vitest"
import { JSDOM } from "jsdom"
import { indexedDB } from "fake-indexeddb"
import {
  testExports,
  handleSendingPublicKey,
  handleChatInput,
  decryptChatEntriesText,
} from "../utils/chat.mjs"
import {
  convertPublicKeyToString,
  decryptMessage,
  encryptMessage,
  generateNewKeyPair,
} from "../utils/security.mjs"
import { storeObject } from "../utils/front-end-database.mjs"
import { querySelectorArrayOf } from "../utils/dom-utils.mjs"
import { Constants } from "../utils/constants.mjs"

const html = `
  <form id="chat-form">
    <input type="hidden" id="text-from" />
    <input type="hidden" id="text-to" />
    <input type-"text" id="chat-text" />
  </form>
`

describe("handleSendingPublicKey", () => {
  it("should return an error when the keys are not present", async () => {
    const event = {
      detail: {},
    }

    try {
      await handleSendingPublicKey(event)
      expect.fail("It should have thrown an exception")
    } catch (_e) {
      /* test passing */
    }
  })

  it("handleSendingPublicKey should store the public key", async () => {
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

    await handleSendingPublicKey(event)

    const currentPublicKeyFromModule = testExports.getCurrentPublicKey()
    const selectedPublicKeyFromModule = testExports.getSelectedPublicKey()

    expect(currentPublicKeyFromModule).toBeTruthy()
    expect(currentPublicKeyFromModule).toBeTruthy()
    expect(selectedPublicKeyFromModule).toBeTruthy()

    expect(await convertPublicKeyToString(currentPublicKeyFromModule)).toBe(currentPublicKeyString)
    expect(await convertPublicKeyToString(selectedPublicKeyFromModule)).toBe(
      selectedPublicKeyString,
    )
  })
})

describe("handleChatInput", () => {
  it(" should encrypt and set the values of hidden inputs", async () => {
    const { publicKey: currentPublicKey, privateKey: currentPrivateKey } =
      await generateNewKeyPair()

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

    await handleSendingPublicKey(publicKeysSendingEvent)

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

      expect(hiddenTextFrom.value).not.toBe("")
      expect(hiddenTextTo.value).not.toBe("")

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

    await handleSendingPublicKey(publicKeysSendingEvent)

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

describe("Chat entries decryption", () => {
  const messageHtml = (encryptedText, dataConverted) => `
    <div>
      <p
        data-message="from"
        data-converted="${dataConverted}"
        class="text-sm text-left break-word w-max max-w-[calc(100vw-62px)] sm:max-w-[450px] font-normal text-zinc-50"
      >
        ${encryptedText}&lrm;
      </p>
    </div>
  `

  it("decryptChatEntryText should decrypt the chat message inside the p element", async () => {
    const { privateKey, publicKey } = await generateNewKeyPair()

    const message = "some message"
    const encryptedMessage = await encryptMessage(message, publicKey)

    const html = messageHtml(encryptedMessage, "false")
    const dom = new JSDOM(html)

    global.document = dom.window.document

    // prettier-ignore
    const element = document.querySelector("[data-converted=\"false\"]")

    await testExports.decryptChatEntryText(element, privateKey)

    // prettier-ignore
    const unconvertedElement = document.querySelector("[data-converted=\"false\"]")
    // prettier-ignore
    const convertedElement = document.querySelector("[data-converted=\"true\"]")

    expect(unconvertedElement).toBeNull()
    expect(convertedElement.innerHTML).toEqual(message)
    expect(convertedElement.dataset.converted).toEqual("true")
  })

  const chatEntriesContainer = (entries) => {
    let string = "<div>"

    for (const entry of entries) {
      string = `${string}${entry}`
    }

    return `${string}</div>`
  }

  it("decryptChatEntriesText should decrypt the chat entries", async () => {
    const sessionName = "some-other-session-name"
    const { privateKey, publicKey } = await generateNewKeyPair()

    global.indexedDB = indexedDB

    await storeObject(Constants.dbName, Constants.tableName, sessionName, privateKey)

    const messages = await Promise.all(
      ["0", "1", "2", "3", "4"]
        .map((i) => `Some message ${i}`)
        .map((m) => encryptMessage(m, publicKey)),
    )

    const messageEntries = messages.map((m) => messageHtml(m, "false"))

    const html = chatEntriesContainer(messageEntries)

    const dom = new JSDOM(html)

    global.document = dom.window.document

    await decryptChatEntriesText(sessionName)

    // prettier-ignore
    const convertedElements = querySelectorArrayOf("[data-converted=\"true\"]")
    // prettier-ignore
    const unconvertedElements = querySelectorArrayOf("[data-converted=\"false\"]")

    expect(convertedElements.length).toEqual(5)
    expect(unconvertedElements.length).toEqual(0)

    convertedElements.forEach((element, i) => {
      const expectedMessage = `Some message ${String(i)}`
      expect(element.innerHTML).toEqual(expectedMessage)
      expect(element.dataset.converted).toEqual("true")
    })
  })

  it("decryptChatEntriesText should decrypt only the chat entries not yet converted", async () => {
    const sessionName = "some-session-name"
    const { privateKey, publicKey } = await generateNewKeyPair()

    global.indexedDB = indexedDB

    await storeObject(Constants.dbName, Constants.tableName, sessionName, privateKey)

    const messages = await Promise.all(
      ["0", "1", "2", "3", "4"]
        .map((i) => `Some message ${i}`)
        .map((m) => encryptMessage(m, publicKey)),
    )

    const messageEntries = messages.map((m, i) => messageHtml(m, i < 2 ? "false" : "true"))

    const html = chatEntriesContainer(messageEntries)

    const dom = new JSDOM(html)

    global.document = dom.window.document

    await decryptChatEntriesText(sessionName)

    // prettier-ignore
    const convertedElements = querySelectorArrayOf("[data-converted=\"true\"]")
    // prettier-ignore
    const unconvertedElements = querySelectorArrayOf("[data-converted=\"false\"]")

    expect(convertedElements.length).toEqual(5)
    expect(unconvertedElements.length).toEqual(0)

    convertedElements.forEach((element, i) => {
      const expectedMessage = `Some message ${String(i)}`

      if (i < 2) {
        expect(element.innerHTML).toEqual(expectedMessage)
      } else {
        expect(element.innerHTML).not.toEqual(expectedMessage)
      }

      expect(element.dataset.converted).toEqual("true")
    })
  })
})
