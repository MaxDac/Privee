import { describe, it, expect, vi, afterEach } from "vitest"
import { JSDOM } from "jsdom"
import {
  addSessionNameCopyListener,
  copySessionNameToClipboardBackEndEventHandler,
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

describe("addSessionNameCopyListener", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("the button click results in the session name copy to the clipboard invocation", () => {
    const sessionName = "some-session-name"

    const buttonHtml = `
    <button data-session-name="${sessionName}">Some button</button>
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

    const dom = new JSDOM(buttonHtml)

    vi.stubGlobal("dom", dom)
    vi.stubGlobal("document", dom.window.document)
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
