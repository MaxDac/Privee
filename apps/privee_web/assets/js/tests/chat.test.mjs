import "fake-indexeddb/auto"
import "./signal-wasm-setup.mjs"
import { IDBFactory } from "fake-indexeddb"
import { JSDOM } from "jsdom"
import { describe, it, expect, beforeEach, vi } from "vitest"
import { ChatController } from "../utils/chat.mjs"
import { catalogTexts, installCatalog } from "./gettext-fixture.mjs"
import { refreshClientTexts } from "../utils/locale.mjs"
import { SignalClient } from "../utils/signal-client.mjs"
import { createMemoryLocks } from "../utils/signal-locks.mjs"
import { FakeServer } from "./signal-fake-server.mjs"

const ALICE = 1
const BOB = 2
const Texts = catalogTexts()

const layout = (/** @type {string} */ epoch) => `
  <div id="chat-banner"></div>
  <button id="chat-safety-number"></button>
  <button id="chat-hint"></button>
  <div id="chat-peer-hint"></div>
  <button id="chat-clear-history"></button>
  <button id="chat-forget-device"></button>
  <button id="chat-export"></button>
  <main id="chat-screen" data-epoch="${epoch}">
    <div id="chat-local-history"></div>
    <div id="chat-screen-container"></div>
  </main>
  <ul id="chat-commands" hidden></ul>
  <span id="chat-vim-mode" hidden></span>
  <input id="chat-text" disabled />
  <button id="chat-send" disabled></button>
`

/**
 * Renders a server message like `chat_entry.html.heex`.
 * @param {Document} doc
 * @param {any} message Serialized server message.
 */
const appendEntry = (doc, message) => {
  const p = doc.createElement("p")
  p.id = `chat-message-${message.id}`
  p.setAttribute("data-signal-message", "")
  Object.assign(p.dataset, {
    id: message.id,
    seq: String(message.seq),
    epoch: message.epoch,
    type: String(message.type),
    body: message.body,
    direction: message.direction,
    converted: "false",
  })
  if (message.client_nonce) p.dataset.clientNonce = message.client_nonce
  p.className = "hidden"
  p.innerHTML = "&lrm;"
  doc.getElementById("chat-screen-container")?.append(p)
  return p
}

/**
 * @param {FakeServer} server
 * @param {number} ownId
 * @param {number} peerId
 * @param {IDBFactory} [factory]
 */
const party = async (server, ownId, peerId, factory = new IDBFactory()) => {
  const dom = new JSDOM(`<body>${layout(server.currentEpoch(ownId, peerId))}</body>`)
  const doc = dom.window.document
  installCatalog(doc)
  const client = await SignalClient.open({
    ownId,
    push: server.connect(ownId, peerId),
    locks: createMemoryLocks(),
    factory,
  })
  const el = /** @type {HTMLElement} */ (doc.getElementById("chat-screen"))
  const controller = new ChatController({
    el,
    client,
    peerId,
    confirm: () => true,
    reload: vi.fn(),
  })
  return { doc, client, controller, factory }
}

/**
 * Streams every message of the conversation not yet in the DOM.
 * @param {FakeServer} server
 * @param {Document} doc
 * @param {number} viewer
 */
const stream = (server, doc, viewer) => {
  for (const m of server.messages) {
    if (doc.getElementById(`chat-message-${m.id}`)) continue
    appendEntry(doc, server.serialize(m, viewer))
  }
}

/** @param {Document} doc */
const texts = (doc) =>
  [...doc.querySelectorAll("[data-signal-message]")].map((el) => el.textContent)

describe("ChatController", () => {
  /** @type {FakeServer} */
  let server

  beforeEach(() => {
    server = new FakeServer()
    vi.spyOn(console, "warn").mockImplementation(() => {})
  })

  it("enables the composer once keys are ready", async () => {
    const alice = await party(server, ALICE, BOB)
    await alice.controller.start()
    expect(/** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text")).disabled).toBe(
      false,
    )
  })

  it("lists the conversation locally and edits its hint from the header", async () => {
    const alice = await party(server, ALICE, BOB)
    alice.controller.peerName = "bob-session"
    const editHint = vi.fn(() => Promise.resolve({ action: "save", hint: "<b>the plumber</b>" }))
    alice.controller.editHint = /** @type {any} */ (editHint)
    await alice.controller.start()
    expect((await alice.client.listConversations()).map((c) => c.name)).toEqual(["bob-session"])
    expect(alice.doc.getElementById("chat-peer-hint")?.children).toHaveLength(0)

    alice.doc.getElementById("chat-hint")?.click()
    await vi.waitFor(() =>
      expect(alice.doc.getElementById("chat-peer-hint-text")?.textContent).toBe(
        "<b>the plumber</b>",
      ),
    )
    expect(editHint).toHaveBeenCalledWith(alice.doc, { current: null })
    expect(alice.doc.querySelector("#chat-peer-hint b")).toBeNull()

    editHint.mockResolvedValueOnce(/** @type {any} */ ({ action: "remove" }))
    alice.doc.getElementById("chat-hint")?.click()
    await vi.waitFor(() => expect(alice.doc.getElementById("chat-peer-hint-text")).toBeNull())
    expect(await alice.client.peerHint(BOB)).toBeNull()
    expect(editHint).toHaveBeenLastCalledWith(alice.doc, { current: "<b>the plumber</b>" })
  })

  it("switches existing client presentation without reinitializing keys or scrolling", async () => {
    const alice = await party(server, ALICE, BOB)
    await alice.controller.start()
    alice.controller.showBanner("notice", alice.controller.texts.noPeerKeys)
    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "draft stays private"
    alice.controller.el.scrollTop = 123
    const ensureKeys = vi.spyOn(alice.client, "ensureKeys")
    installCatalog(alice.doc, "it")
    refreshClientTexts(alice.doc)
    await alice.controller.processEntries()
    expect(alice.controller.el.scrollTop).toBe(123)
    expect(input.value).toBe("draft stays private")
    expect(input.disabled).toBe(false)
    expect(ensureKeys).not.toHaveBeenCalled()
    expect(alice.doc.getElementById("chat-banner-notice")?.textContent).toContain(
      catalogTexts("it").noPeerKeys,
    )
    await alice.client.close()
  })

  it("sends from the composer and renders both sides", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()

    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "  hello <b>bob</b>  "
    await alice.controller.sendFromComposer()
    expect(input.value).toBe("")

    stream(server, alice.doc, ALICE)
    stream(server, bob.doc, BOB)
    await alice.controller.processEntries()
    await bob.controller.processEntries()

    expect(texts(alice.doc)).toEqual(["hello <b>bob</b>"])
    expect(texts(bob.doc)).toEqual(["hello <b>bob</b>"])
    expect(bob.doc.querySelector("b")).toBeNull()
    const entry = /** @type {HTMLElement} */ (bob.doc.querySelector("[data-signal-message]"))
    expect(entry.dataset.converted).toBe("true")
    expect(entry.classList.contains("hidden")).toBe(false)
  })

  it("renders markdown safely in received messages", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()

    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "**hi** see https://example.com and [x](javascript:alert(1)) <img src=x>"
    await alice.controller.sendFromComposer()
    stream(server, bob.doc, BOB)
    await bob.controller.processEntries()

    const entry = /** @type {HTMLElement} */ (bob.doc.querySelector("[data-signal-message]"))
    expect(entry.querySelector("strong")?.textContent).toBe("hi")
    const links = [...entry.querySelectorAll("a")]
    expect(links.map((a) => a.getAttribute("href"))).toEqual(["https://example.com/"])
    expect(links[0].rel).toContain("noopener")
    expect(entry.querySelector("img")).toBeNull()
    expect(entry.textContent).toBe(
      "hi see https://example.com and [x](javascript:alert(1)) <img src=x>",
    )
  })

  it("runs commands locally without sending them", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    const input = /** @type {HTMLInputElement} */ (bob.doc.getElementById("chat-text"))

    input.value = ":lo"
    input.dispatchEvent(new bob.doc.defaultView.Event("input"))
    const list = /** @type {HTMLElement} */ (bob.doc.getElementById("chat-commands"))
    expect(list.hidden).toBe(false)
    const suggested = [...list.querySelectorAll("[data-command]")]
    expect(suggested.map((b) => /** @type {HTMLElement} */ (b).dataset.command)).toEqual(["lock"])
    const lockButton = /** @type {HTMLElement} */ (list.querySelector("[data-command=lock]"))
    lockButton.click()
    expect(input.value).toBe(":lock ")
    expect(list.hidden).toBe(true)

    const before = server.messages.length
    input.value = ":vim"
    await bob.controller.sendFromComposer()
    expect(bob.controller.vim?.enabled).toBe(true)
    expect(server.messages).toHaveLength(before)

    input.value = ":)"
    await bob.controller.sendFromComposer()
    expect(server.messages).toHaveLength(before + 1)
  })

  it("locks the screen behind a password and unlocks it from the local history", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()

    const aliceInput = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    aliceInput.value = "top secret"
    await alice.controller.sendFromComposer()
    stream(server, bob.doc, BOB)
    await bob.controller.processEntries()
    expect(texts(bob.doc)).toEqual(["top secret"])

    const input = /** @type {HTMLInputElement} */ (bob.doc.getElementById("chat-text"))
    input.value = ":lock"
    await bob.controller.sendFromComposer()
    expect(bob.doc.getElementById("chat-banner-notice")?.textContent).toContain(
      Texts.lockNeedsPassword,
    )

    input.value = ":lock hunter2"
    await bob.controller.sendFromComposer()
    const entry = /** @type {HTMLElement} */ (bob.doc.querySelector("[data-signal-message]"))
    expect(entry.textContent).toBe(entry.dataset.body)
    expect(entry.dataset.locked).toBe("true")
    expect(bob.doc.body.textContent).not.toContain("top secret")

    aliceInput.value = "still secret"
    await alice.controller.sendFromComposer()
    stream(server, bob.doc, BOB)
    await bob.controller.processEntries()
    expect(bob.doc.body.textContent).not.toContain("still secret")

    input.value = ":unlock wrong"
    await bob.controller.sendFromComposer()
    expect(bob.doc.getElementById("chat-banner-notice")?.textContent).toContain(Texts.wrongPassword)
    expect(bob.doc.body.textContent).not.toContain("top secret")

    input.value = ":unlock hunter2"
    await bob.controller.sendFromComposer()
    expect(texts(bob.doc)).toEqual(["top secret", "still secret"])
    expect(bob.doc.getElementById("chat-banner-locked")).toBeNull()
  })

  it("exports the local history as CSV", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    alice.controller.peerName = "bob session"
    const download = vi.fn()
    alice.controller.download = download
    await alice.controller.start()
    await bob.controller.start()

    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "=HYPERLINK(1), hi"
    await alice.controller.sendFromComposer()

    alice.doc.getElementById("chat-export")?.click()
    await vi.waitFor(() => expect(download).toHaveBeenCalled())
    const [filename, csv] = download.mock.calls[0]
    expect(filename).toMatch(/^privee-bob_session-\d{4}-\d{2}-\d{2}\.csv$/)
    const lines = csv.trim().split("\r\n")
    expect(lines[0]).toBe("timestamp,direction,message")
    expect(lines[1]).toMatch(/^\d{4}-.*Z,sent,"'=HYPERLINK\(1\), hi"$/)
  })

  it("keeps the text and warns when the peer has no keys", async () => {
    const alice = await party(server, ALICE, BOB)
    await alice.controller.start()
    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "anyone?"
    await alice.controller.sendFromComposer()
    expect(input.value).toBe("anyone?")
    expect(alice.doc.getElementById("chat-banner-notice")?.textContent).toContain(Texts.noPeerKeys)
  })

  it("keeps the text when sending fails before the message is queued", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {})
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    server.intercept.set("open_conversation", () => ({ error: "unavailable" }))

    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "retry me"
    await alice.controller.sendFromComposer()
    expect(input.value).toBe("retry me")
    expect(alice.doc.getElementById("chat-banner-notice")?.textContent).toContain(Texts.sendFailed)
    expect(await alice.client.pendingOutbox(BOB)).toHaveLength(0)
  })

  it("does not ask to retry a queued message, which is delivered once later", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {})
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    server.intercept.set("send_message", () => ({ error: "unavailable" }))

    const input = /** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text"))
    input.value = "queued"
    await alice.controller.sendFromComposer()
    expect(input.value).toBe("")
    expect(alice.doc.getElementById("chat-banner-notice")?.textContent).toContain(Texts.sendQueued)
    expect(await alice.client.pendingOutbox(BOB)).toHaveLength(1)

    server.intercept.delete("send_message")
    await alice.controller.flush()
    expect(server.inbox(BOB, ALICE)).toHaveLength(1)
    expect(await alice.client.pendingOutbox(BOB)).toHaveLength(0)
  })

  it("renders own messages after a reload from the local history", async () => {
    const factory = new IDBFactory()
    const alice = await party(server, ALICE, BOB, factory)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    await alice.client.send(BOB, "persisted")

    const reloaded = await party(server, ALICE, BOB, factory)
    stream(server, reloaded.doc, ALICE)
    await reloaded.controller.start()
    expect(texts(reloaded.doc)).toEqual(["persisted"])
  })

  it("shows a placeholder for own messages sent from another device", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    await alice.client.send(BOB, "hi")

    const otherDevice = await party(server, ALICE, BOB)
    stream(server, otherDevice.doc, ALICE)
    await otherDevice.controller.start()
    expect(texts(otherDevice.doc)).toEqual([Texts.unavailable])
  })

  it("catches up with messages older than the server window into local history", async () => {
    const alice = await party(server, ALICE, BOB)
    await alice.controller.start()
    const bob = await party(server, BOB, ALICE)
    await bob.controller.start()

    for (const text of ["1", "2", "3"]) await alice.client.send(BOB, text)
    // The server stream only renders the latest message.
    appendEntry(bob.doc, server.serialize(server.messages[2], BOB))
    await bob.controller.start()

    expect(texts(bob.doc)).toEqual(["3"])
    const earlier = bob.doc.getElementById("chat-local-history")
    expect(earlier?.textContent).toContain(Texts.earlier)
    expect(
      [...(earlier?.querySelectorAll("[data-local-history]") || [])].map((e) => e.textContent),
    ).toEqual(["1", "2"])
  })

  it("blocks on an identity change until the user accepts it", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    await alice.client.send(BOB, "hello")
    stream(server, bob.doc, BOB)
    await bob.controller.processEntries()

    const alice2 = await party(server, ALICE, BOB)
    await alice2.client.ensureKeys()
    await alice2.client.resetIdentity()
    await alice2.client.send(BOB, "new device")

    stream(server, bob.doc, BOB)
    await bob.controller.processEntries()
    const banner = bob.doc.getElementById("chat-banner-identity")
    expect(banner).not.toBeNull()
    expect(banner?.textContent).toMatch(/\d{5} \d{5}/)
    expect(/** @type {HTMLInputElement} */ (bob.doc.getElementById("chat-text")).disabled).toBe(
      true,
    )

    await bob.controller.approveIdentity()
    expect(bob.doc.getElementById("chat-banner-identity")).toBeNull()
    expect(texts(bob.doc)).toEqual(["hello", "new device"])
  })

  it("shows the superseded banner when another device resets the identity", async () => {
    const factory = new IDBFactory()
    const alice = await party(server, ALICE, BOB, factory)
    await alice.controller.start()

    const other = await party(server, ALICE, BOB)
    await other.client.ensureKeys()
    await other.client.resetIdentity()

    await alice.controller.onIdentitySuperseded({ identity_key: await other.client.identityKey() })
    expect(alice.doc.getElementById("chat-banner-superseded")).not.toBeNull()
    expect(/** @type {HTMLInputElement} */ (alice.doc.getElementById("chat-text")).disabled).toBe(
      true,
    )

    // Resetting on this device makes it the active one again.
    alice.doc.getElementById("chat-banner-superseded-action")?.click()
    await vi.waitFor(() => expect(alice.controller.state).toBe("ready"))
    expect(alice.doc.getElementById("chat-banner-superseded")).toBeNull()
  })

  it("clears the local history and forgets the device", async () => {
    const alice = await party(server, ALICE, BOB)
    const bob = await party(server, BOB, ALICE)
    await alice.controller.start()
    await bob.controller.start()
    await alice.client.send(BOB, "bye")

    await alice.controller.clearHistory()
    expect(await alice.client.history(BOB)).toEqual([])

    await alice.controller.forgetDevice()
    expect(alice.controller.reload).toHaveBeenCalled()
    const names = (await alice.factory.databases()).map((d) => d.name)
    expect(names).not.toContain(`privee-${ALICE}`)
  })
})
