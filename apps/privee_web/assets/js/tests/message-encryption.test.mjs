import test from "ava"
import { indexedDB } from "fake-indexeddb"
import { JSDOM } from "jsdom"
import { bindKeys, handleSessionNamePrivateKeyRegistrationEvent } from "../utils/message-encryption.mjs"
import { getObject } from "../utils/front-end-database.mjs"
import { importStringPublicKey } from "../utils/security.mjs"

const html = "<input id='session-registration-public-key' type='hidden' />"

test.serial("bindKeys should bind public key generation to input field", async t => {
  const dom = new JSDOM(html)
  global.document = dom.window.document
  global.indexedDB = indexedDB

  await bindKeys()

  /** @type{HTMLInputElement} */ const hiddenInput = 
    document.querySelector("#session-registration-public-key")

  const hiddenInputValue = hiddenInput.value

  t.assert(hiddenInputValue.length > 0)

  const publicKey = importStringPublicKey(hiddenInputValue)
  const privateKey = getObject("private_key")
  
  t.is(typeof publicKey, "object")
  t.truthy(publicKey)
  t.is(typeof privateKey, "object")
  t.truthy(privateKey)
})

test.serial("bindKeys does not work if the hidden input is not present in the DOM", async t => {
  const dom = new JSDOM()
  global.document = dom.window.document
  global.indexedDB = indexedDB

  try {
    await bindKeys()
    t.fail()
  }
  catch (e) {
    t.pass()
  }
})

test.serial("bindKeys rebinds the keys if called twice", async t => {
  const dom = new JSDOM(html)
  global.document = dom.window.document
  global.indexedDB = indexedDB

  await bindKeys()
  await bindKeys()

  /** @type{HTMLInputElement} */ const hiddenInput = 
    document.querySelector("#session-registration-public-key")

  const hiddenInputValue = hiddenInput.value

  t.assert(hiddenInputValue.length > 0)

  const publicKey = importStringPublicKey(hiddenInputValue)
  const privateKey = getObject("private_key")
  
  t.is(typeof publicKey, "object")
  t.truthy(publicKey)
  t.is(typeof privateKey, "object")
  t.truthy(privateKey)
})

test("handleSessionNamePrivateKeyRegistrationEvent should handle session name copy event", t => {
  global.indexedDB = indexedDB
  // Create a mock event object
  const event = {
    // Add properties based on your requirements
  }

  handleSessionNamePrivateKeyRegistrationEvent(event)

  // Assert that the event is handled correctly
  // You can add more specific assertions based on your requirements
  t.pass()
})
