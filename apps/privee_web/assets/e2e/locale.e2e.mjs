import { test, expect } from "@playwright/test"
import {
  waitForLiveView,
  registerUser,
  openChat,
  send,
  expectMessage,
  expectNoPlaintextOnTheWire,
} from "./helpers.mjs"

test("language switching preserves registration/login drafts, cookie and live navigation", async ({
  page,
}) => {
  await page.goto("/")
  await waitForLiveView(page)
  await page.locator("#session_recovery_phrase").fill("a draft citation that must remain unchanged")
  const name = await page.locator("#session_session_name").inputValue()
  await page.locator("#settings-toggle").click()
  for (const locale of ["it", "pt-PT", "es", "fr", "en"]) {
    await page.locator("#language-select").selectOption(locale)
    await expect(page.locator("html")).toHaveAttribute("lang", locale)
    await expect(page.locator("#session_recovery_phrase")).toHaveValue(
      "a draft citation that must remain unchanged",
    )
    await expect(page.locator("#session_session_name")).toHaveValue(name)
    await expect(page).toHaveURL(/\/$/)
  }
  await page.locator("#language-select").selectOption("fr")
  await expect(page.locator("html")).toHaveAttribute("lang", "fr")
  await page.locator("a[href='/login']").first().click()
  await expect(page.locator("html")).toHaveAttribute("lang", "fr")
  await page.locator("#session_session_name").fill("login-draft")
  await page.locator("#session_recovery_phrase").fill("login phrase")
  await page.locator("#session_remember_me").check()
  await page.locator("#settings-toggle").click()
  await page.locator("#language-select").selectOption("it")
  await expect(page.locator("html")).toHaveAttribute("lang", "it")
  await expect(page.locator("#session_session_name")).toHaveValue("login-draft")
  await expect(page.locator("#session_recovery_phrase")).toHaveValue("login phrase")
  await expect(page.locator("#session_remember_me")).toBeChecked()
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("lang", "it")
  await page.locator("a[href='/']").first().click()
  await waitForLiveView(page)
  await page
    .locator("#session_recovery_phrase")
    .fill("a new valid recovery phrase preserved in its own language")
  await page.locator("#registration_form button[name=action]").click()
  await page.waitForURL(/\/privee$/)
  await expect(page.locator("html")).toHaveAttribute("lang", "it")
  await page.locator("#privee_form_session_name").fill("contact-draft")
  await page.locator("#settings-toggle").click()
  await page.locator("#language-select").selectOption("pt-PT")
  await expect(page.locator("html")).toHaveAttribute("lang", "pt-PT")
  await expect(page.locator("#privee_form_session_name")).toHaveValue("contact-draft")
  await page.locator("a[href='/sessions/log_out']").click()
  await expect(page.locator("html")).toHaveAttribute("lang", "pt-PT")
})

test("switches encrypted chat in place without replacing plaintext, draft or encryption state", async ({
  browser,
}) => {
  const alice = await registerUser(browser, "locale-alice")
  const bob = await registerUser(browser, "locale-bob")
  try {
    await openChat(alice, bob)
    await openChat(bob, alice)
    const message = "a private message never translated"
    const draft = "a private composer draft"
    await send(alice, message)
    await expectMessage(alice, message)
    await expectMessage(bob, message)
    for (let i = 0; i < 12; i++) {
      await send(alice, `scrollable history ${i} ${"long private text ".repeat(60)}`)
    }
    await expectMessage(alice, `scrollable history 11 ${"long private text ".repeat(60)}`)
    await alice.page.locator("#chat-text").fill(draft)
    await alice.page.locator("#chat-safety-number").click()
    const safety = await alice.page.locator("#chat-banner-safety .font-mono").textContent()
    if (!safety) throw new Error("The safety number was not rendered")
    const url = alice.page.url()
    const scrolling = await alice.page.locator("#chat-screen").evaluate((el) => {
      el.scrollTop = 0
      return el.scrollHeight > el.clientHeight
    })
    expect(scrolling, "the history is actually scrollable").toBe(true)
    await alice.page.locator("#settings-toggle").click()
    for (const locale of ["it", "pt-PT", "es", "fr", "en"]) {
      await alice.page.locator("#language-select").selectOption(locale)
      await expect(alice.page.locator("html")).toHaveAttribute("lang", locale)
      await expect(alice.page.locator("#chat-text")).toHaveValue(draft)
      await expect(alice.page.locator("#chat-text")).toBeEnabled()
      await expect(alice.page.locator("#chat-banner-safety .font-mono")).toHaveText(safety)
      await expectMessage(alice, message)
      expect(await alice.page.locator("#chat-screen").evaluate((el) => el.scrollTop)).toBe(0)
      expect(alice.page.url()).toBe(url)
    }
    await alice.page.locator("#language-select").selectOption("fr")
    await expect(alice.page.locator("html")).toHaveAttribute("lang", "fr")
    await alice.page.evaluate(() => {
      // @ts-ignore - LiveSocket is exposed by the bundled app.
      window.liveSocket.disconnect()
      // @ts-ignore - LiveSocket is exposed by the bundled app.
      window.liveSocket.connect()
    })
    await waitForLiveView(alice.page)
    await expect(alice.page.locator("html")).toHaveAttribute("lang", "fr")
    await expect(alice.page.locator("#chat-text")).toHaveValue(draft)
    await alice.page.locator("#chat-send").click()
    await expectMessage(bob, draft)
    expectNoPlaintextOnTheWire([alice, bob], [message, draft])
    await alice.page.locator("a[href='/sessions/log_out']").click()
    await expect(alice.page.locator("html")).toHaveAttribute("lang", "fr")
  } finally {
    await alice.context.close()
    await bob.context.close()
  }
})
