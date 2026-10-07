import { expect, test } from "@playwright/test"
import { expectNoErrors, registerUser } from "./helpers.mjs"

test("registers a session and lands on the privee selector", async ({ browser }) => {
  const user = await registerUser(browser, "Alice")

  try {
    await expect(user.page.locator("#privee_form")).toBeVisible()
    expectNoErrors([user])
  } finally {
    await user.context.close()
  }
})
