import { expect } from "@playwright/test"

/**
 * @typedef {object} User
 * @property {string} label Name used in assertion messages.
 * @property {string} sessionName Session name chosen at registration.
 * @property {import("@playwright/test").BrowserContext} context Isolated browser profile.
 * @property {import("@playwright/test").Page} page
 * @property {string[]} errors Console and page errors seen so far.
 * @property {string[]} frames WebSocket frames sent and received so far.
 */

const RECOVERY_PHRASE = "the quick brown fox jumps over the lazy dog"

/**
 * Registers a new session in its own browser context, so every user has a
 * separate cookie jar and IndexedDB (i.e. a separate Signal device).
 * @param {import("@playwright/test").Browser} browser
 * @param {string} label
 * @returns {Promise<User>}
 */
export async function registerUser(browser, label) {
  const context = await browser.newContext()
  const page = await context.newPage()

  /** @type {string[]} */
  const errors = []
  /** @type {string[]} */
  const frames = []

  page.on("console", (message) => {
    // Phoenix live reload logs through console.error in development.
    if (message.type() === "error" && !message.text().includes("📡")) {
      errors.push(`${label}: ${message.text()}`)
    }
  })
  page.on("pageerror", (error) => errors.push(`${label}: ${error.message}`))
  page.on("websocket", (socket) => {
    socket.on("framesent", (frame) => frames.push(String(frame.payload)))
    socket.on("framereceived", (frame) => frames.push(String(frame.payload)))
  })

  await page.goto("/")
  await waitForLiveView(page)

  const form = page.locator("#registration_form")
  const sessionName = await form.locator("input[name$='[session_name]']").inputValue()
  expect(sessionName, `${label} gets a generated session name`).not.toBe("")

  await form.locator("textarea").fill(RECOVERY_PHRASE)
  await form.getByRole("button", { name: "Create an account" }).click()
  await page.waitForURL(/\/privee$/)
  await waitForLiveView(page)

  return { label, sessionName, context, page, errors, frames }
}

/**
 * Waits until the main LiveView is connected, so hooks and events are live.
 * @param {import("@playwright/test").Page} page
 */
export async function waitForLiveView(page) {
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
}

/**
 * Opens the chat with `peer` and waits until the composer is enabled, which
 * happens once this device's Signal keys are published.
 * @param {User} user
 * @param {User} peer
 */
export async function openChat(user, peer) {
  await user.page.goto(`/chat/${peer.sessionName}`)
  await expectComposerReady(user)
}

/**
 * Waits until the chat composer accepts input.
 * @param {User} user
 */
export async function expectComposerReady(user) {
  await expect(user.page.locator("#chat-text"), `${user.label} can write`).toBeEnabled({
    timeout: 30_000,
  })
}

/**
 * Sends a message through the composer and waits until it is accepted.
 * @param {User} user
 * @param {string} text
 */
export async function send(user, text) {
  const input = user.page.locator("#chat-text")
  await input.fill(text)
  await user.page.locator("#chat-send").click()
  await expect(input).toHaveValue("")
}

/**
 * Waits until `text` is visible in the user's conversation.
 * @param {User} user
 * @param {string} text
 */
export async function expectMessage(user, text) {
  await expect(
    user.page.locator("#chat-screen").getByText(text).first(),
    `${user.label} sees "${text}"`,
  ).toBeVisible()
}

/**
 * Asserts that none of `secrets` ever crossed the users' WebSockets in clear.
 * @param {User[]} users
 * @param {string[]} secrets
 */
export function expectNoPlaintextOnTheWire(users, secrets) {
  const frames = users.flatMap((user) => user.frames)
  expect(frames.length, "WebSocket traffic was captured").toBeGreaterThan(0)

  const leaks = frames.filter((frame) => secrets.some((secret) => frame.includes(secret)))
  expect(leaks, "no plaintext in WebSocket frames").toEqual([])
}

/**
 * Asserts that no console or page errors were reported.
 * @param {User[]} users
 */
export function expectNoErrors(users) {
  expect(
    users.flatMap((user) => user.errors),
    "no console errors",
  ).toEqual([])
}
