import { describe, it, expect, vi, afterEach } from "vitest"
import { JSDOM } from "jsdom"
import {
  testExports,
  handlePreKeyBundle,
  handleChatInput,
  decryptChatEntriesText,
} from "../utils/chat.mjs"
import {
  generateRegistrationKeys,
  exportPreKeyBundle,
  initSendingSession,
  initReceivingSession,
  x3dhInitiate,
  ratchetEncrypt,
  generateSigningKeyPair,
} from "../utils/signal-protocol.mjs"
import * as signalStore from "../utils/signal-store.mjs"

const html = `
  <form id="chat-form">
    <input type="hidden" id="chat-ciphertext" />
    <input type="hidden" id="chat-header" />
    <input type="text" id="chat-text" />
  </form>
`

describe("handlePreKeyBundle", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    testExports.setCurrentSession(null)
    testExports.setCurrentPeerSessionId(null)
  })

  it("should warn and return when no peer_session_id present", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {})

    await handlePreKeyBundle({ detail: { peer_session_id: null } })

    expect(warnSpy).toHaveBeenCalledWith("No prekey bundle available for peer")
    expect(testExports.getCurrentSession()).toBeNull()
  })

  it("should load existing session if one exists for the peer", async () => {
    const mockSession = { rootKey: "mock" }
    vi.spyOn(signalStore, "getSession").mockResolvedValue(mockSession)
    vi.spyOn(signalStore, "getIdentityKeyPair").mockResolvedValue(null)

    await handlePreKeyBundle({
      detail: {
        peer_session_id: "peer-123",
        identity_key: "fake",
        signed_prekey: { key_id: 1, public_key: "fake", signature: "fake" },
        one_time_prekey: null,
      },
    })

    expect(testExports.getCurrentSession()).toBe(mockSession)
  })

  it("should establish new session via X3DH when no existing session", async () => {
    // Generate real keys for the peer (Bob)
    const bobKeys = await generateRegistrationKeys(1)
    const bobBundle = await exportPreKeyBundle(bobKeys)

    // Generate identity key pair for Alice (local)
    const aliceIdentity = await generateSigningKeyPair()

    vi.spyOn(signalStore, "getSession").mockResolvedValue(null)
    vi.spyOn(signalStore, "getIdentityKeyPair").mockResolvedValue({
      publicKey: aliceIdentity.publicKey,
      privateKey: aliceIdentity.privateKey,
    })
    vi.spyOn(signalStore, "storeSession").mockResolvedValue(undefined)

    await handlePreKeyBundle({
      detail: {
        peer_session_id: "peer-456",
        identity_key: bobBundle.identityKey,
        signed_prekey: {
          key_id: bobBundle.signedPreKey.keyId,
          public_key: bobBundle.signedPreKey.publicKey,
          signature: bobBundle.signedPreKey.signature,
        },
        one_time_prekey: bobBundle.oneTimePreKeys[0]
          ? {
              key_id: bobBundle.oneTimePreKeys[0].keyId,
              public_key: bobBundle.oneTimePreKeys[0].publicKey,
            }
          : null,
      },
    })

    expect(testExports.getCurrentSession()).not.toBeNull()
    expect(signalStore.storeSession).toHaveBeenCalledWith("peer-456", expect.anything())
  })
})

describe("handleChatInput", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    testExports.setCurrentSession(null)
    testExports.setCurrentPeerSessionId(null)
  })

  it("should do nothing when key is not Enter", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("KeyboardEvent", dom.window.KeyboardEvent)

    await handleChatInput(new KeyboardEvent("keypress", { key: "a" }))

    const ciphertextInput = document.querySelector("#chat-ciphertext")
    expect(ciphertextInput.value).toBe("")
  })

  it("should clear hidden inputs when chat text is empty", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("Event", dom.window.Event)
    vi.stubGlobal("KeyboardEvent", dom.window.KeyboardEvent)

    // Set up a session
    const bobKeys = await generateRegistrationKeys(1)
    const bobBundle = await exportPreKeyBundle(bobKeys)
    const aliceIdentity = await generateSigningKeyPair()
    const { sharedSecret } = await x3dhInitiate(aliceIdentity.privateKey, {
      identity_key: bobBundle.identityKey,
      signed_prekey: {
        public_key: bobBundle.signedPreKey.publicKey,
        signature: bobBundle.signedPreKey.signature,
      },
      one_time_prekey: bobBundle.oneTimePreKeys[0],
    })
    const session = await initSendingSession(sharedSecret, bobBundle.signedPreKey.publicKey)
    testExports.setCurrentSession(session)
    testExports.setCurrentPeerSessionId("peer-1")
    vi.spyOn(signalStore, "storeSession").mockResolvedValue(undefined)

    const chatText = document.querySelector("#chat-text")
    chatText.value = ""

    const event = new KeyboardEvent("keypress", { key: "Enter", cancelable: true })
    await handleChatInput(event)

    const ciphertextInput = document.querySelector("#chat-ciphertext")
    const headerInput = document.querySelector("#chat-header")
    expect(ciphertextInput.value).toBe("")
    expect(headerInput.value).toBe("")
  })

  it("should encrypt and set hidden inputs when session exists", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("Event", dom.window.Event)
    vi.stubGlobal("KeyboardEvent", dom.window.KeyboardEvent)

    // Set up a session
    const bobKeys = await generateRegistrationKeys(1)
    const bobBundle = await exportPreKeyBundle(bobKeys)
    const aliceIdentity = await generateSigningKeyPair()
    const { sharedSecret } = await x3dhInitiate(aliceIdentity.privateKey, {
      identity_key: bobBundle.identityKey,
      signed_prekey: {
        public_key: bobBundle.signedPreKey.publicKey,
        signature: bobBundle.signedPreKey.signature,
      },
      one_time_prekey: bobBundle.oneTimePreKeys[0],
    })
    const session = await initSendingSession(sharedSecret, bobBundle.signedPreKey.publicKey)
    testExports.setCurrentSession(session)
    testExports.setCurrentPeerSessionId("peer-1")
    vi.spyOn(signalStore, "storeSession").mockResolvedValue(undefined)

    const chatText = document.querySelector("#chat-text")
    chatText.value = "Hello, world!"

    let formSubmitted = false
    const form = document.querySelector("#chat-form")
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      formSubmitted = true
    })

    const event = new KeyboardEvent("keypress", { key: "Enter", cancelable: true })
    await handleChatInput(event)

    const ciphertextInput = document.querySelector("#chat-ciphertext")
    const headerInput = document.querySelector("#chat-header")

    expect(ciphertextInput.value).not.toBe("")
    expect(headerInput.value).not.toBe("")
    expect(chatText.value).toBe("")
    expect(formSubmitted).toBe(true)
  })

  it("should log error when no session established", async () => {
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("Event", dom.window.Event)
    vi.stubGlobal("KeyboardEvent", dom.window.KeyboardEvent)

    testExports.setCurrentSession(null)

    const chatText = document.querySelector("#chat-text")
    chatText.value = "Hello"

    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})

    const event = new KeyboardEvent("keypress", { key: "Enter", cancelable: true })
    await handleChatInput(event)

    expect(errorSpy).toHaveBeenCalledWith("No Signal session established")
  })
})

describe("decryptChatEntriesText", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    testExports.setCurrentSession(null)
    testExports.setCurrentPeerSessionId(null)
  })

  it("should do nothing when no unconverted entries exist", async () => {
    const dom = new JSDOM("<div></div>")
    vi.stubGlobal("document", dom.window.document)

    await decryptChatEntriesText("session-name")
    // No errors thrown
  })

  it("should do nothing when no session exists", async () => {
    // prettier-ignore
    const dom = new JSDOM("<div data-converted=\"false\" data-ciphertext=\"x\" data-header=\"y\"></div>")
    vi.stubGlobal("document", dom.window.document)

    testExports.setCurrentSession(null)
    await decryptChatEntriesText("session-name")

    // prettier-ignore
    const el = document.querySelector("[data-converted=\"false\"]")
    expect(el).not.toBeNull()
  })

  it("should decrypt entries when a session exists", async () => {
    // Set up paired sessions
    const bobKeys = await generateRegistrationKeys(1)
    const bobBundle = await exportPreKeyBundle(bobKeys)
    const aliceIdentity = await generateSigningKeyPair()
    const { sharedSecret } = await x3dhInitiate(aliceIdentity.privateKey, {
      identity_key: bobBundle.identityKey,
      signed_prekey: {
        public_key: bobBundle.signedPreKey.publicKey,
        signature: bobBundle.signedPreKey.signature,
      },
      one_time_prekey: bobBundle.oneTimePreKeys[0],
    })

    // Alice encrypts
    const aliceSession = await initSendingSession(sharedSecret, bobBundle.signedPreKey.publicKey)
    const { ciphertext, header } = await ratchetEncrypt(aliceSession, "Secret message")

    // Bob session for decryption
    const bobSession = await initReceivingSession(sharedSecret, bobKeys.signedPreKey.keyPair)
    testExports.setCurrentSession(bobSession)
    testExports.setCurrentPeerSessionId("alice-id")
    vi.spyOn(signalStore, "storeSession").mockResolvedValue(undefined)

    // Set up DOM with the encrypted message - use proper attribute escaping
    // prettier-ignore
    const entryEl = "<div><p data-converted=\"false\" class=\"hidden\"></p></div>"
    const dom = new JSDOM(entryEl)
    vi.stubGlobal("document", dom.window.document)

    // Set data attributes programmatically to avoid HTML escaping issues
    const pEl = document.querySelector("p")
    pEl.dataset.ciphertext = ciphertext
    pEl.dataset.header = header

    await decryptChatEntriesText("session-name")

    // prettier-ignore
    const el = document.querySelector("[data-converted=\"true\"]")
    expect(el).not.toBeNull()
    expect(el.textContent).toContain("Secret message")
    expect(el.classList.contains("hidden")).toBe(false)
  })
})
