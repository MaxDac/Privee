import "fake-indexeddb/auto"
import "./signal-wasm-setup.mjs"
import { IDBFactory } from "fake-indexeddb"
import { JSDOM } from "jsdom"
import { describe, it, expect, beforeEach, vi } from "vitest"
import {
  HINT_MAX_LENGTH,
  clearHintsOnSignOut,
  keysLockName,
  normalizeHint,
} from "../utils/peer-hints.mjs"
import { openHintEditor } from "../utils/hint-editor.mjs"
import { renderConversations } from "../utils/conversation-list.mjs"
import { addSignOutHintsCleanup } from "../utils/sign-out.mjs"
import { SignalClient } from "../utils/signal-client.mjs"
import { createMemoryLocks } from "../utils/signal-locks.mjs"
import { dbNameFor } from "../utils/signal-db.mjs"
import { catalogTexts, installCatalog } from "./gettext-fixture.mjs"
import { FakeServer } from "./signal-fake-server.mjs"

const ALICE = 1
const BOB = 2
const Texts = catalogTexts()

const newDocument = () => {
  const doc = new JSDOM("<body></body>").window.document
  installCatalog(doc)
  return doc
}

/** @param {IDBFactory} factory */
const openAlice = (factory, locks = createMemoryLocks()) =>
  SignalClient.open({
    ownId: ALICE,
    push: new FakeServer().connect(ALICE, BOB),
    locks,
    factory,
  })

describe("normalizeHint", () => {
  it("keeps a single trimmed line", () => {
    expect(normalizeHint("  the \t plumber\n from work ")).toBe("the plumber from work")
  })

  it("returns null when blank", () => {
    expect(normalizeHint("")).toBeNull()
    expect(normalizeHint("  \n ")).toBeNull()
    expect(normalizeHint(null)).toBeNull()
  })

  it("removes control and bidirectional override characters", () => {
    expect(normalizeHint("a\u0000b\u202Ec\u2066d")).toBe("abcd")
  })

  it("limits the length in characters, not code units", () => {
    const hint = normalizeHint("😀".repeat(HINT_MAX_LENGTH + 5))
    expect(Array.from(hint ?? "")).toHaveLength(HINT_MAX_LENGTH)
  })
})

describe("clearHintsOnSignOut", () => {
  beforeEach(() => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
  })

  it("removes the hints of the session and keeps its keys", async () => {
    const factory = new IDBFactory()
    const client = await openAlice(factory)
    await client.setPeerName(BOB, "bob-session")
    await client.setPeerHint(BOB, "the plumber")
    client.close()

    await clearHintsOnSignOut(ALICE, { factory, locks: createMemoryLocks() })

    const reopened = await openAlice(factory)
    expect(await reopened.peerHint(BOB)).toBeNull()
    expect((await reopened.listConversations()).map((c) => c.name)).toEqual(["bob-session"])
  })

  it("does not create a database for a session without one", async () => {
    const factory = new IDBFactory()
    await clearHintsOnSignOut(ALICE, { factory, locks: null })
    const names = (await factory.databases()).map((db) => db.name)
    expect(names).not.toContain(dbNameFor(ALICE))
  })

  it("does not wait forever for the keys lock", async () => {
    const factory = new IDBFactory()
    const locks = createMemoryLocks()
    const client = await openAlice(factory, locks)
    await client.setPeerHint(BOB, "the plumber")
    client.close()

    /** @type {() => void} */
    let release = () => {}
    const held = locks.request(
      keysLockName(ALICE),
      { mode: "exclusive" },
      () => new Promise((resolve) => (release = () => resolve(undefined))),
    )
    await clearHintsOnSignOut(ALICE, { factory, locks, timeoutMs: 10 })
    release()
    await held

    expect(await (await openAlice(factory)).peerHint(BOB)).toBeNull()
  })
})

describe("openHintEditor", () => {
  it("advises not to use the contact's name every time it opens", async () => {
    const doc = newDocument()
    for (const current of [null, "the plumber"]) {
      const result = openHintEditor(doc, { current })
      expect(doc.getElementById("hint-editor-advice")?.textContent).toBe(Texts.hintAdvice)
      doc.getElementById("hint-editor-cancel")?.click()
      expect(await result).toBeNull()
      expect(doc.getElementById("hint-editor")).toBeNull()
    }
  })

  it("returns the typed hint on save", async () => {
    const doc = newDocument()
    const result = openHintEditor(doc, { current: "old" })
    const input = /** @type {HTMLInputElement} */ (doc.getElementById("hint-editor-input"))
    expect(input.value).toBe("old")
    expect(input.maxLength).toBe(HINT_MAX_LENGTH)
    input.value = "the plumber"
    doc.getElementById("hint-editor-save")?.click()
    expect(await result).toEqual({ action: "save", hint: "the plumber" })
  })

  it("offers removal only when a hint exists", async () => {
    const doc = newDocument()
    const empty = openHintEditor(doc)
    expect(doc.getElementById("hint-editor-remove")).toBeNull()
    doc.getElementById("hint-editor-cancel")?.click()
    await empty

    const result = openHintEditor(doc, { current: "old" })
    doc.getElementById("hint-editor-remove")?.click()
    expect(await result).toEqual({ action: "remove" })
  })

  it("treats a blank hint as a removal", async () => {
    const doc = newDocument()
    const result = openHintEditor(doc, { current: "old" })
    const input = /** @type {HTMLInputElement} */ (doc.getElementById("hint-editor-input"))
    input.value = "   "
    doc.getElementById("hint-editor-save")?.click()
    expect(await result).toEqual({ action: "remove" })
  })
})

describe("renderConversations", () => {
  const conversations = [
    {
      peerId: BOB,
      name: "bob session/1",
      hint: "<img src=x onerror=alert(1)>",
      lastMessageAt: 1_700_000_000_000,
      lastActivity: 1_700_000_000_000,
    },
    { peerId: 3, name: "carol", hint: null, lastMessageAt: null, lastActivity: 1 },
  ]

  it("renders nothing without conversations", () => {
    const doc = newDocument()
    const container = doc.createElement("div")
    renderConversations(container, [], { onEditHint: vi.fn() })
    expect(container.children).toHaveLength(0)
  })

  it("links each conversation and shows hints as text", () => {
    const doc = newDocument()
    const container = doc.createElement("div")
    doc.body.append(container)
    renderConversations(container, conversations, { onEditHint: vi.fn() })

    expect(doc.getElementById("local-conversations-title")?.textContent).toBe(
      Texts.conversationsTitle,
    )
    const row = doc.getElementById(`conversation-${BOB}`)
    expect(row?.querySelector("a")?.getAttribute("href")).toBe("/chat/bob%20session%2F1")
    expect(row?.querySelector("[data-role=hint]")?.textContent).toBe(conversations[0].hint)
    expect(container.querySelector("img")).toBeNull()
    expect(doc.getElementById("conversation-3")?.querySelector("[data-role=hint]")).toBeNull()
  })

  it("edits the hint of a conversation", () => {
    const doc = newDocument()
    const container = doc.createElement("div")
    const onEditHint = vi.fn()
    renderConversations(container, conversations, { onEditHint })
    container
      .querySelector(`#conversation-${BOB}-hint`)
      ?.dispatchEvent(new doc.defaultView.MouseEvent("click", { bubbles: true }))
    expect(onEditHint).toHaveBeenCalledWith(conversations[0])
  })
})

describe("addSignOutHintsCleanup", () => {
  it("clears the hints once before following the sign-out link", async () => {
    const doc = newDocument()
    const link = doc.createElement("a")
    link.id = "log-out-link"
    link.href = "/sessions/log_out"
    link.dataset.ownSessionId = "7"
    doc.body.append(link)

    const followed = vi.fn()
    doc.addEventListener("click", (event) => {
      if (!event.defaultPrevented) followed()
      event.preventDefault()
    })
    const clearHints = vi.fn(() => Promise.resolve())
    const remove = addSignOutHintsCleanup(doc, clearHints)

    link.click()
    expect(clearHints).toHaveBeenCalledWith("7")
    expect(followed).not.toHaveBeenCalled()

    await vi.waitFor(() => expect(followed).toHaveBeenCalledTimes(1))
    expect(clearHints).toHaveBeenCalledTimes(1)
    remove()
  })

  it("signs out even when clearing fails", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    const doc = newDocument()
    const link = doc.createElement("a")
    link.id = "log-out-link"
    link.dataset.ownSessionId = "7"
    doc.body.append(link)
    const followed = vi.fn()
    doc.addEventListener("click", (event) => {
      if (!event.defaultPrevented) followed()
      event.preventDefault()
    })
    const remove = addSignOutHintsCleanup(doc, () => Promise.reject(new Error("boom")))

    link.click()
    await vi.waitFor(() => expect(followed).toHaveBeenCalledTimes(1))
    remove()
  })
})
