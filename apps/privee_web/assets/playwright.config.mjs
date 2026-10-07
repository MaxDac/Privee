import { defineConfig, devices } from "@playwright/test"
import { fileURLToPath } from "node:url"

const port = process.env.PORT || "4000"
const externalBaseURL = process.env.E2E_BASE_URL
const baseURL = externalBaseURL || `http://localhost:${port}`
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url))

// Browser tests for the real application. By default Playwright starts the server
// with `mix phx.server` from the repository root (configure it through MIX_ENV,
// DATABASE_URL, SECRET_KEY_BASE, ...); set E2E_BASE_URL to test a running server.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.e2e.mjs",
  outputDir: "./test-results",
  timeout: 120_000,
  expect: { timeout: 20_000 },
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  // Chats live in node-local ETS: run the scenarios one at a time against one server.
  workers: 1,
  reporter: process.env.CI
    ? [["github"], ["list"], ["html", { open: "never", outputFolder: "playwright-report" }]]
    : [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        ...(process.env.E2E_BROWSER_CHANNEL ? { channel: process.env.E2E_BROWSER_CHANNEL } : {}),
      },
    },
  ],
  webServer: externalBaseURL
    ? undefined
    : {
        command: "mix phx.server",
        cwd: repoRoot,
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 180_000,
        stdout: "pipe",
        stderr: "pipe",
      },
})
