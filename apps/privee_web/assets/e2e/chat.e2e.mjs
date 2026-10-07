import { expect, test } from "@playwright/test"
import {
  expectComposerReady,
  expectMessage,
  expectNoErrors,
  expectNoPlaintextOnTheWire,
  openChat,
  registerUser,
  send,
} from "./helpers.mjs"

/** @type {import("./helpers.mjs").User[]} */
let users = []

test.afterEach(async () => {
  await Promise.all(users.map((user) => user.context.close()))
  users = []
})

test("exchanges end-to-end encrypted messages in both directions", async ({ browser }) => {
  const alice = await registerUser(browser, "Alice")
  const bob = await registerUser(browser, "Bob")
  users = [alice, bob]

  await openChat(alice, bob)
  await openChat(bob, alice)

  await test.step("Alice to Bob", async () => {
    await send(alice, "hello from alice secret-alpha")
    await expectMessage(bob, "secret-alpha")
  })

  await test.step("Bob to Alice", async () => {
    await send(bob, "reply from bob secret-bravo")
    await expectMessage(alice, "secret-bravo")
  })

  await test.step("a burst arrives complete and in order", async () => {
    const burst = ["burst-one", "burst-two", "burst-three"]
    for (const text of burst) await send(alice, text)
    for (const text of burst) await expectMessage(bob, text)

    const transcript = (await bob.page.locator("#chat-screen").textContent()) || ""
    const positions = burst.map((text) => transcript.indexOf(text))
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })

  expectNoPlaintextOnTheWire(users, ["secret-alpha", "secret-bravo", "burst-one", "burst-three"])
  expectNoErrors(users)
})

test("delivers to an offline recipient and keeps history across reloads", async ({ browser }) => {
  const alice = await registerUser(browser, "Alice")
  const bob = await registerUser(browser, "Bob")
  users = [alice, bob]

  await openChat(alice, bob)
  await openChat(bob, alice)
  await send(alice, "first message secret-charlie")
  await expectMessage(bob, "secret-charlie")

  await test.step("Bob is away while Alice writes", async () => {
    await bob.page.goto("/privee")
    await send(alice, "while you were away secret-delta")
    await openChat(bob, alice)
    await expectMessage(bob, "secret-delta")
  })

  await test.step("history survives a reload on both sides", async () => {
    await Promise.all([alice.page.reload(), bob.page.reload()])
    await expectComposerReady(alice)
    await expectComposerReady(bob)

    await expectMessage(alice, "secret-charlie")
    await expectMessage(bob, "secret-delta")

    await send(bob, "after reload secret-echo")
    await expectMessage(alice, "secret-echo")
  })

  expectNoPlaintextOnTheWire(users, ["secret-charlie", "secret-delta", "secret-echo"])
  expectNoErrors(users)
})
