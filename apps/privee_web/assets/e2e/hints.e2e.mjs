import { expect, test } from "@playwright/test"
import {
  expectNoErrors,
  expectNoPlaintextOnTheWire,
  openChat,
  registerUser,
  send,
  waitForLiveView,
} from "./helpers.mjs"

/** @type {import("./helpers.mjs").User[]} */
let users = []

test.afterEach(async () => {
  await Promise.all(users.map((user) => user.context.close()))
  users = []
})

/**
 * Reads the peer metadata of `ownId` from this browser's IndexedDB.
 * @param {import("@playwright/test").Page} page
 * @param {string} ownId
 * @returns {Promise<Record<string, any>[]>}
 */
const peerMeta = (page, ownId) =>
  page.evaluate(
    (id) =>
      new Promise((resolve, reject) => {
        const open = indexedDB.open(`privee-${id}`)
        open.onerror = () => reject(open.error)
        open.onsuccess = () => {
          const db = open.result
          const out = /** @type {Record<string, any>[]} */ ([])
          const cursor = db.transaction("meta").objectStore("meta").openCursor()
          cursor.onsuccess = () => {
            const c = cursor.result
            if (!c) {
              db.close()
              resolve(out)
              return
            }
            if (String(c.key).startsWith("peer:")) out.push(c.value)
            c.continue()
          }
          cursor.onerror = () => reject(cursor.error)
        }
      }),
    ownId,
  )

test("keeps a local hint about who is speaking until sign-out", async ({ browser }) => {
  const alice = await registerUser(browser, "Alice")
  const bob = await registerUser(browser, "Bob")
  users = [alice, bob]
  const hint = "met at the climbing gym secret-hint"

  await openChat(alice, bob)
  await openChat(bob, alice)
  await send(alice, "hello")

  await test.step("the editor advises against names and saves the hint", async () => {
    await alice.page.locator("#chat-hint").click()
    await expect(alice.page.locator("#hint-editor-advice")).toBeVisible()
    await expect(alice.page.locator("#hint-editor-advice")).toContainText("Don't use their name")
    await alice.page.locator("#hint-editor-input").fill(hint)
    await alice.page.locator("#hint-editor-save").click()
    await expect(alice.page.locator("#hint-editor")).toHaveCount(0)
    await expect(alice.page.locator("#chat-peer-hint-text")).toHaveText(hint)
  })

  await test.step("the conversation and its hint are listed on this browser", async () => {
    await alice.page.goto("/privee")
    await waitForLiveView(alice.page)
    const row = alice.page.locator("#local-conversations-list li").filter({
      hasText: bob.sessionName,
    })
    await expect(row).toHaveCount(1)
    await expect(row.locator("[data-role=hint]")).toHaveText(hint)

    await row.locator("a").click()
    await expect(alice.page).toHaveURL(new RegExp(`/chat/${bob.sessionName}$`))
    await expect(alice.page.locator("#chat-peer-hint-text")).toHaveText(hint)
  })

  await test.step("the editor advises again every time it opens", async () => {
    await alice.page.locator("#chat-hint").click()
    await expect(alice.page.locator("#hint-editor-advice")).toBeVisible()
    await expect(alice.page.locator("#hint-editor-input")).toHaveValue(hint)
    await alice.page.locator("#hint-editor-cancel").click()
    await expect(alice.page.locator("#hint-editor")).toHaveCount(0)
  })

  await test.step("sign-out removes the hint but keeps the keys", async () => {
    const ownId = await alice.page.locator("#log-out-link").getAttribute("data-own-session-id")
    if (!ownId) throw new Error("The sign-out link has no session id")
    expect((await peerMeta(alice.page, ownId)).some((meta) => meta.hint)).toBe(true)

    await alice.page.locator("a[href='/sessions/log_out']").click()
    await alice.page.waitForURL((url) => !url.pathname.startsWith("/chat"))

    const metas = await peerMeta(alice.page, ownId)
    expect(metas.map((meta) => meta.name)).toContain(bob.sessionName)
    expect(metas.filter((meta) => "hint" in meta)).toEqual([])
  })

  expectNoPlaintextOnTheWire(users, ["secret-hint", "climbing gym"])
  expectNoErrors(users)
})
