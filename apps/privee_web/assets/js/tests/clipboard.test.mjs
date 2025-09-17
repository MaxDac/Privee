import { describe, it, expect, vi, afterEach } from "vitest"
import { JSDOM } from "jsdom"
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

describe("copyButtonHandler", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("copies session name when action is 'code'", () => {
    const sessionName = "test-session"
    let copiedText = null

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: (text) => {
          copiedText = text
          return Promise.resolve()
        },
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: "code",
      },
    }

    testExports.copyButtonHandler.call(mockButton)

    expect(copiedText).toBe(sessionName)
  })

  it("copies session URL when action is not 'code'", () => {
    const sessionName = "test-session"
    let copiedText = null

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: (text) => {
          copiedText = text
          return Promise.resolve()
        },
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: "url",
      },
    }

    testExports.copyButtonHandler.call(mockButton)

    expect(copiedText).toBe("https://example.com/share/test-session")
  })

  it("copies session URL when no action is specified", () => {
    const sessionName = "test-session"
    let copiedText = null

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: (text) => {
          copiedText = text
          return Promise.resolve()
        },
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        // no action property
      },
    }

    testExports.copyButtonHandler.call(mockButton)

    expect(copiedText).toBe("https://example.com/share/test-session")
  })

  it("copies session URL when action is undefined", () => {
    const sessionName = "test-session"
    let copiedText = null

    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: (text) => {
          copiedText = text
          return Promise.resolve()
        },
      },
    })

    const mockButton = {
      dataset: {
        sessionName: sessionName,
        action: undefined,
      },
    }

    testExports.copyButtonHandler.call(mockButton)

    expect(copiedText).toBe("https://example.com/share/test-session")
  })
})

describe("addSessionNameCopyListener", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("the button click with action='code' results in the session name copy to the clipboard invocation", () => {
    const sessionName = "some-session-name"

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="code">Copy button</button>
    `

    let copiedText = null

    const copyHandler = (text) => {
      copiedText = text
      return Promise.resolve()
    }

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: copyHandler,
      },
    })

    addSessionNameCopyListener()

    const button = document.querySelector("[data-session-name]")
    button.click()

    expect(copiedText).toBe(sessionName)
  })

  it("the button click with action='url' results in the session URL copy to the clipboard invocation", () => {
    const sessionName = "some-session-name"

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="url">URL button</button>
    `

    let copiedText = null

    const copyHandler = (text) => {
      copiedText = text
      return Promise.resolve()
    }

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: copyHandler,
      },
    })

    addSessionNameCopyListener()

    const button = document.querySelector("[data-session-name]")
    button.click()

    expect(copiedText).toBe("https://example.com/share/some-session-name")
  })

  it("the button click without action defaults to URL copy to the clipboard invocation", () => {
    const sessionName = "some-session-name"

    const buttonHtml = `
    <button data-session-name="${sessionName}">Some button</button>
    `

    let copiedText = null

    const copyHandler = (text) => {
      copiedText = text
      return Promise.resolve()
    }

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: copyHandler,
      },
    })

    addSessionNameCopyListener()

    const button = document.querySelector("[data-session-name]")
    button.click()

    expect(copiedText).toBe("https://example.com/share/some-session-name")
  })
})

describe("addSessionNameCopyListener - Original Test Behavior", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("the button click results in the session name copy to the clipboard invocation", () => {
    const sessionName = "some-session-name"

    const buttonHtml = `
    <button data-session-name="${sessionName}" data-action="code">Some button</button>
    `

    let result = false

    const copyHandler = (text) => {
      if (text === sessionName) {
        result = true
        return Promise.resolve()
      } else {
        return Promise.reject("The text is not what was expected.")
      }
    }

    const dom = new JSDOM(buttonHtml, { url: "https://example.com" })

    vi.stubGlobal("dom", dom)
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("window", dom.window)
    vi.stubGlobal("navigator", {
      ...dom.window.navigator,
      clipboard: {
        writeText: copyHandler,
      },
    })

    addSessionNameCopyListener()

    const button = document.querySelector("[data-session-name]")
    // @ts-ignore
    button.click()

    expect(result).toBe(true)
  })
})
