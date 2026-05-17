import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { getDom } from "./mock-utils.mjs"

// We test getTabPriority, electWinner directly, and the coordinator via its public API.

describe("getTabPriority", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it("returns 3 for a focused chat tab matching the session", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "bauta-chat-alice" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })

    const { getTabPriority } = await import("../utils/notification-coordinator.mjs")
    expect(getTabPriority("alice")).toBe(3)
  })

  it("returns 2 for an unfocused chat tab matching the session", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "bauta-chat-alice" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => false })

    const { getTabPriority } = await import("../utils/notification-coordinator.mjs")
    expect(getTabPriority("alice")).toBe(2)
  })

  it("returns 1 for a focused tab that is not the chat tab for that session", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })

    const { getTabPriority } = await import("../utils/notification-coordinator.mjs")
    expect(getTabPriority("alice")).toBe(1)
  })

  it("returns 0 for an unfocused non-chat tab", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => false })

    const { getTabPriority } = await import("../utils/notification-coordinator.mjs")
    expect(getTabPriority("alice")).toBe(0)
  })
})

describe("electWinner", () => {
  it("picks the highest priority claim", async () => {
    const { electWinner } = await import("../utils/notification-coordinator.mjs")
    const claims = [
      { priority: 1, claimantTabId: "aaa" },
      { priority: 3, claimantTabId: "bbb" },
      { priority: 2, claimantTabId: "ccc" },
    ]
    expect(electWinner(claims).claimantTabId).toBe("bbb")
  })

  it("breaks ties with lowest tabId (lexicographic)", async () => {
    const { electWinner } = await import("../utils/notification-coordinator.mjs")
    const claims = [
      { priority: 1, claimantTabId: "zzz" },
      { priority: 1, claimantTabId: "aaa" },
      { priority: 1, claimantTabId: "mmm" },
    ]
    expect(electWinner(claims).claimantTabId).toBe("aaa")
  })

  it("handles a single claim", async () => {
    const { electWinner } = await import("../utils/notification-coordinator.mjs")
    const claims = [{ priority: 0, claimantTabId: "solo" }]
    expect(electWinner(claims).claimantTabId).toBe("solo")
  })
})

describe("createNotificationCoordinator", () => {
  /** @type {Array<Array<any>>} */
  let channelInstances

  beforeEach(() => {
    channelInstances = []

    vi.stubGlobal(
      "BroadcastChannel",
      class MockBroadcastChannel {
        /**
         * @param {string} name
         */
        constructor(name) {
          this.name = name
          this.onmessage = null
          channelInstances.push(this)
        }

        /**
         * @param {any} data
         */
        postMessage(data) {
          for (const peer of channelInstances) {
            if (peer !== this && peer.name === this.name && peer.onmessage) {
              peer.onmessage({ data })
            }
          }
        }

        close() {
          const idx = channelInstances.indexOf(this)
          if (idx !== -1) channelInstances.splice(idx, 1)
        }
      },
    )
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    channelInstances = []
  })

  it("allows notification when BroadcastChannel is not available", async () => {
    vi.stubGlobal("BroadcastChannel", undefined)

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    const result = await coordinator.shouldShowNotification("alice")
    expect(result).toBe(true)

    coordinator.destroy()
  })

  it("allows notification when there is only one tab", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-1" })

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    const result = await coordinator.shouldShowNotification("alice")
    expect(result).toBe(true)

    coordinator.destroy()
  })

  it("first tab wins, second is suppressed via 'shown' broadcast", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => false })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-1" })

    const mod = await import("../utils/notification-coordinator.mjs")
    const coordinator1 = mod.createNotificationCoordinator()

    vi.stubGlobal("crypto", { randomUUID: () => "tab-2" })
    const coordinator2 = mod.createNotificationCoordinator()

    // First coordinator claims and wins (no competing higher-priority claims)
    const result1 = await coordinator1.shouldShowNotification("alice")
    expect(result1).toBe(true)

    // Second coordinator should be suppressed by the dedup window
    // (coordinator1 broadcast "shown" which coordinator2 received)
    const result2 = await coordinator2.shouldShowNotification("alice")
    expect(result2).toBe(false)

    coordinator1.destroy()
    coordinator2.destroy()
  })

  it("suppresses duplicate notifications within the dedup window on same coordinator", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-solo" })

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    const first = await coordinator.shouldShowNotification("alice")
    expect(first).toBe(true)

    const second = await coordinator.shouldShowNotification("alice")
    expect(second).toBe(false)

    coordinator.destroy()
  })

  it("rejects undefined/null sessionName", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-guard" })

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    const result1 = await coordinator.shouldShowNotification(undefined)
    expect(result1).toBe(false)

    const result2 = await coordinator.shouldShowNotification(null)
    expect(result2).toBe(false)

    coordinator.destroy()
  })

  it("destroy cleans up pending elections", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-destroy" })

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    const promise = coordinator.shouldShowNotification("alice")
    coordinator.destroy()

    const result = await promise
    expect(result).toBe(false)
  })

  it("coalesces concurrent same-tab calls for the same sessionName", async () => {
    const dom = getDom()
    vi.stubGlobal("window", { ...dom.window, name: "" })
    vi.stubGlobal("document", { ...dom.window.document, hasFocus: () => true })
    vi.stubGlobal("crypto", { randomUUID: () => "tab-coalesce" })

    const { createNotificationCoordinator } = await import("../utils/notification-coordinator.mjs")
    const coordinator = createNotificationCoordinator()

    // Call twice concurrently for the same sessionName — both should resolve
    // without hanging. The first (initiating) call gets the election result,
    // coalesced calls always resolve false to prevent same-tab duplicates.
    const [result1, result2] = await Promise.all([
      coordinator.shouldShowNotification("alice"),
      coordinator.shouldShowNotification("alice"),
    ])

    expect(result1).toBe(true)
    expect(result2).toBe(false)

    coordinator.destroy()
  })
})
