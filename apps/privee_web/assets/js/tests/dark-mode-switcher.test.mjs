import { describe, it, expect, beforeAll, beforeEach } from "vitest"
import { addDarkModeToggleHandlers, setStartupTheme } from "../utils/dark-mode-switcher.mjs"
import { getDom } from "./mock-utils.mjs"

const html = `
  <button id="theme-toggle" aria-label="dark-theme-selector" data-theme-toggle="theme-toggle">
    <svg id="theme-toggle-dark-icon" data-theme-selector="dark" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
      <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z"></path>
    </svg>
    <svg id="theme-toggle-light-icon" data-theme-selector="light" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
      <path d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" fill-rule="evenodd" clip-rule="evenodd">
      </path>
    </svg>
  </button>
  `

/**
 * Gets the toggle button in the mocked DOM.
 * @returns {HTMLButtonElement} The button element.
 */
// prettier-ignore
const getToggleButton = () => document.querySelector("[data-theme-toggle=\"theme-toggle\"]")

beforeAll(() => {
  const dom = getDom(html)
  const { window } = dom

  global.dom = dom
  // @ts-ignore
  global.window = {
    ...window,
    // @ts-ignore
    matchMedia: (query) => ({
      matches: query === "(prefers-color-scheme: light)",
    }),
  }

  global.document = dom.window.document

  // global.localStorage = getLocalStorageMock()
  global.localStorage = dom.window.localStorage
})

beforeEach(() => {
  // Clearing local storage before each test
  localStorage.clear()
})

describe("setStartupTheme", () => {
  it("select automatically the light mode", () => {
    setStartupTheme()

    // prettier-ignore
    const lightElementClassList = document.querySelector("[data-theme-selector=\"light\"]").classList
    // prettier-ignore
    const darkElementClassList = document.querySelector("[data-theme-selector=\"dark\"]").classList
    const htmlElementClassList = document.getElementsByTagName("html").item(0).classList

    expect(global.localStorage.getItem("color-theme")).toBe("light")
    expect(lightElementClassList.contains("hidden"))
    expect(!darkElementClassList.contains("hidden"))
    expect(htmlElementClassList.contains("light"))
  })

  it("automatically select light theme when it's configured in local storage", () => {
    global.localStorage.setItem("color-theme", "dark")
    setStartupTheme()

    // prettier-ignore
    const lightElementClassList = document.querySelector("[data-theme-selector=\"light\"]").classList
    // prettier-ignore
    const darkElementClassList = document.querySelector("[data-theme-selector=\"dark\"]").classList
    const htmlElementClassList = document.getElementsByTagName("html").item(0).classList

    expect(global.localStorage.getItem("color-theme")).toBe("dark")
    expect(!lightElementClassList.contains("hidden"))
    expect(darkElementClassList.contains("hidden"))
    expect(htmlElementClassList.contains("dark"))
  })

  it("toggle to dark mode when button is pressed", () => {
    localStorage.clear()
    setStartupTheme()
    addDarkModeToggleHandlers()

    // prettier-ignore
    let lightElementClassList = document.querySelector("[data-theme-selector=\"light\"]").classList
    // prettier-ignore
    let darkElementClassList = document.querySelector("[data-theme-selector=\"dark\"]").classList
    let htmlElementClassList = document.getElementsByTagName("html").item(0).classList

    expect(global.localStorage.getItem("color-theme")).toBe("light")
    expect(lightElementClassList.contains("hidden"))
    expect(!darkElementClassList.contains("hidden"))
    expect(htmlElementClassList.contains("light"))

    // Clicking the item should toggle the theme
    getToggleButton().click()

    // prettier-ignore
    lightElementClassList = document.querySelector("[data-theme-selector=\"light\"]").classList
    // prettier-ignore
    darkElementClassList = document.querySelector("[data-theme-selector=\"dark\"]").classList
    htmlElementClassList = document.getElementsByTagName("html").item(0).classList

    expect(global.localStorage.getItem("color-theme")).toBe("dark")
    expect(!lightElementClassList.contains("hidden"))
    expect(darkElementClassList.contains("hidden"))
    expect(htmlElementClassList.contains("dark"))

    // Clicking the item should toggle the theme back
    getToggleButton().click()

    // prettier-ignore
    lightElementClassList = document.querySelector("[data-theme-selector=\"light\"]").classList
    // prettier-ignore
    darkElementClassList = document.querySelector("[data-theme-selector=\"dark\"]").classList
    htmlElementClassList = document.getElementsByTagName("html").item(0).classList

    expect(global.localStorage.getItem("color-theme")).toBe("light")
    expect(lightElementClassList.contains("hidden"))
    expect(!darkElementClassList.contains("hidden"))
    expect(htmlElementClassList.contains("light"))
  })
})
