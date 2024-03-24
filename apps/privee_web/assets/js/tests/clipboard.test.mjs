import test from "ava"
import { JSDOM } from "jsdom"
import { beforeEach, describe } from "node:test"
import { addSessionNameCopyListener, copySessionNameToClipboardBackEndEventHandler } from "../utils/clipboard.mjs"

describe("clipboard", () => {
  test("copy session name to clipboard following back end event", t => {
    const sessionName = "session name"
    
    const dom = new JSDOM()
    global.navigator = {
      ...dom.window.navigator,
      clipboard: {
        ...dom.window.navigator.clipboard,
        writeText: text => {
          if (text === sessionName) {
            return Promise.resolve()
          } else {
            return Promise.reject("The text is not what was expected.")
          }
        }
      }
    }
    
    const event = { detail: { session_name: sessionName } }
    
    return copySessionNameToClipboardBackEndEventHandler(event)
      .then(_ => t.pass())
      .catch(e => t.fail(e))
  })

  test("copy session name to clipboard correctly report the error", t => {
    const sessionName = "session name"
    const errorMessage = "some error"
    const copyError = new Error(errorMessage)
    
    const dom = new JSDOM()
    global.navigator = {
      ...dom.window.navigator,
      clipboard: {
        ...dom.window.navigator.clipboard,
        writeText: _text => Promise.reject(copyError)
      }
    }
    
    const event = { detail: { session_name: sessionName } }
    
    return copySessionNameToClipboardBackEndEventHandler(event)
      .then(_ => t.fail("The copy operation should not have succeeded"))
      .catch(e => t.pass())
  })
})

describe("Add copy listener to copy session buttons", () => {
  const sessionName = "some-session-name"

  const buttonHtml = `
  <button data-session-name="${sessionName}">Some button</button>
  `

  test("The button click results in the session name copy to the clipboard invocation", t => {
    let result = false

    const copyHandler = text => {
      if (text === sessionName) {
        result = true
        return Promise.resolve()
      } else {
        return Promise.reject("The text is not what was expected.")
      }
    }

    const dom = new JSDOM(buttonHtml)

    global.dom = dom

    global.document = dom.window.document

    global.navigator = {
      ...dom.window.navigator,
      clipboard: {
        ...dom.window.navigator.clipboard,
        writeText: copyHandler
      }
    }

    addSessionNameCopyListener()

    const button = document.querySelector("[data-session-name]")
    // @ts-ignore
    button.click()

    t.true(result)
  })
})
