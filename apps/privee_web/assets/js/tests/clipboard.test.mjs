import { describe, it, expect, vi, afterEach } from "vitest"
import { JSDOM } from "jsdom"

// Mock the flash-hooks module to avoid phoenix_live_view dependency
vi.mock("../hooks/flash-hooks.mjs", () => ({
  pushFlash: vi.fn(),
}))

import {
  addSessionNameCopyListener,
  copySessionNameToClipboardBackEndEventHandler,
  testExports,
} from "../utils/clipboard.mjs"

describe("copySessionNameToClipboardBackEndEventHandler", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("copy session name to clipboard following back end event", () => {
    const sessionName = "session name"

    const dom = new JSDOM()

    const mockNavigator = {
      ...dom.window.navigator,
      clipboard: {
        writeText: (text) => {
          if (text === sessionName) {
            return Promise.resolve()
          } else {
            return Promise.reject("The text is not what was expected.")
          }
        },
      },
    }

    vi.stubGlobal("navigator", mockNavigator)

    const event = { detail: { session_name: sessionName } }

    return copySessionNameToClipboardBackEndEventHandler(event).catch((e) => expect.fail(e))
  })

  it("copy session name to clipboard correctly report the error", async () => {
    const sessionName = "session name"
    const errorMessage = "some error"
    const copyError = new Error(errorMessage)

    const dom = new JSDOM()

    const mockNavigator = {
      ...dom.window.navigator,
      clipboard: {
        writeText: (_text) => Promise.reject(copyError),
      },
    }

    vi.stubGlobal("navigator", mockNavigator)

    const event = { detail: { session_name: sessionName } }

    try {
      await copySessionNameToClipboardBackEndEventHandler(event)
      expect.fail("The copy operation should not have succeeded")
    } catch (e) {
      expect(e).toBe(copyError)
    }
  })
})

describe("getSessionLoginMarkdownLink", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("generates correct URL with basic inputs", () => {
    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)

    const result = testExports.getSessionLoginMarkdownLink("abc123", "Login Here")
    expect(result).toBe("https://example.com/share/abc123")
  })

  it("properly encodes special characters in session code", () => {
    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)

    const result = testExports.getSessionLoginMarkdownLink("test@#$%", "Session Link")
    expect(result).toBe("https://example.com/share/test%40%23%24%25")
  })

  it("handles different host origins", () => {
    const dom = new JSDOM("", { url: "http://localhost:4000" })
    vi.stubGlobal("window", dom.window)

    const result = testExports.getSessionLoginMarkdownLink("session123", "Dev Link")
    expect(result).toBe("http://localhost:4000/share/session123")
  })

  it("handles empty title (title parameter ignored)", () => {
    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)

    const result = testExports.getSessionLoginMarkdownLink("abc123", "")
    expect(result).toBe("https://example.com/share/abc123")
  })
})

describe("createCopyButtonHandler", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("copies session name when action is 'code'", async () => {
    const sessionName = "test-session"
    const mockPushFlash = vi.fn().mockResolvedValue(undefined)
    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: mockWriteText,
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: "code",
      },
    }

    const handler = testExports.createCopyButtonHandler(mockPushFlash)
    await handler.call(mockButton)

    expect(mockWriteText).toHaveBeenCalledWith(sessionName)
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Session copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("copies session URL when action is not 'code'", async () => {
    const sessionName = "test-session"
    const mockPushFlash = vi.fn().mockResolvedValue(undefined)
    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: mockWriteText,
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: "url",
      },
    }

    const handler = testExports.createCopyButtonHandler(mockPushFlash)
    await handler.call(mockButton)

    expect(mockWriteText).toHaveBeenCalledWith("https://example.com/share/test-session")
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Url copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("copies session URL when no action is specified", async () => {
    const sessionName = "test-session"
    const mockPushFlash = vi.fn().mockResolvedValue(undefined)
    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: mockWriteText,
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        // no action property
      },
    }

    const handler = testExports.createCopyButtonHandler(mockPushFlash)
    await handler.call(mockButton)

    expect(mockWriteText).toHaveBeenCalledWith("https://example.com/share/test-session")
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Url copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("copies session URL when action is undefined", async () => {
    const sessionName = "test-session"
    const mockPushFlash = vi.fn().mockResolvedValue(undefined)
    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: mockWriteText,
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: undefined,
      },
    }

    const handler = testExports.createCopyButtonHandler(mockPushFlash)
    await handler.call(mockButton)

    expect(mockWriteText).toHaveBeenCalledWith("https://example.com/share/test-session")
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Url copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })
})

describe("addSessionNameCopyListener - Original Test Behavior", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("the button click results in the session name copy to the clipboard invocation", async () => {
    const sessionName = "some-session-name"
    const mockPushFlash = vi.fn().mockResolvedValue(undefined)

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="code">Some button</button>
    `

    const mockWriteText = vi.fn((text) => {
      if (text === sessionName) {
        return Promise.resolve()
      } else {
        return Promise.reject("The text is not what was expected.")
      }
    })

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    addSessionNameCopyListener(mockPushFlash)

    const button = document.querySelector("[data-session-name][data-action]")
    await button.click()

    // Wait for any promises to resolve
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(mockWriteText).toHaveBeenCalledWith(sessionName)
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })
})

describe("addSessionNameCopyListener", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("the button click with action='code' results in the session name copy to the clipboard invocation", async () => {
    const sessionName = "some-session-name"
    const mockPushFlash = vi.fn()

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="code">Copy button</button>
    `

    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    addSessionNameCopyListener(mockPushFlash)

    const button = document.querySelector("[data-session-name][data-action]")
    await button.click()

    // Wait for any promises to resolve
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(mockWriteText).toHaveBeenCalledWith(sessionName)
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Session copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("the button click with action='url' results in the session URL copy to the clipboard invocation", async () => {
    const sessionName = "some-session-name"
    const mockPushFlash = vi.fn()

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="url">URL button</button>
    `

    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    addSessionNameCopyListener(mockPushFlash)

    const button = document.querySelector("[data-session-name][data-action]")
    await button.click()

    // Wait for any promises to resolve
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(mockWriteText).toHaveBeenCalledWith("https://example.com/share/some-session-name")
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Url copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("the button click without action defaults to URL copy to the clipboard invocation", async () => {
    const sessionName = "some-session-name"
    const mockPushFlash = vi.fn()

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="">Some button</button>
    `

    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    addSessionNameCopyListener(mockPushFlash)

    const button = document.querySelector("[data-session-name][data-action]")
    await button.click()

    // Wait for any promises to resolve
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(mockWriteText).toHaveBeenCalledWith("https://example.com/share/some-session-name")
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Url copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })

  it("multiple buttons can be clicked and each triggers the appropriate action", async () => {
    const sessionName1 = "session-one"
    const sessionName2 = "session-two"
    const mockPushFlash = vi.fn()

    const buttonHtml = `
    <button data-session-name="${sessionName1}" data-action="code">Copy Code</button>
    <button data-session-name="${sessionName2}" data-action="url">Copy URL</button>
    `

    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    addSessionNameCopyListener(mockPushFlash)

    const buttons = document.querySelectorAll("[data-session-name][data-action]")

    // Click first button (code action)
    await buttons[0].click()
    await new Promise((resolve) => setTimeout(resolve, 0))

    // Click second button (url action)
    await buttons[1].click()
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(mockWriteText).toHaveBeenCalledTimes(2)
    expect(mockWriteText).toHaveBeenNthCalledWith(1, sessionName1)
    expect(mockWriteText).toHaveBeenNthCalledWith(2, "https://example.com/share/session-two")

    expect(mockPushFlash).toHaveBeenCalledTimes(2)
    expect(mockPushFlash).toHaveBeenNthCalledWith(1, "Info", "Session copied")
    expect(mockPushFlash).toHaveBeenNthCalledWith(2, "Info", "Url copied")
  })

  it("properly cleans up event listeners when called multiple times", async () => {
    const sessionName = "test-session"
    const mockPushFlash = vi.fn()

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="code">Copy button</button>
    `

    const mockWriteText = vi.fn().mockResolvedValue(undefined)

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: mockWriteText,
      },
    })

    // Call addSessionNameCopyListener multiple times
    addSessionNameCopyListener(mockPushFlash)
    addSessionNameCopyListener(mockPushFlash)
    addSessionNameCopyListener(mockPushFlash)

    const button = document.querySelector("[data-session-name][data-action]")
    await button.click()

    // Wait for any promises to resolve
    await new Promise((resolve) => setTimeout(resolve, 0))

    // Should only be called once despite multiple listener additions
    expect(mockWriteText).toHaveBeenCalledWith(sessionName)
    expect(mockWriteText).toHaveBeenCalledTimes(1)
    expect(mockPushFlash).toHaveBeenCalledWith("Info", "Session copied")
    expect(mockPushFlash).toHaveBeenCalledTimes(1)
  })
})
