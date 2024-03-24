import test from "ava"
import { setStartupTheme } from "../utils/dark-mode-switcher.mjs"
import { getDom } from "./mock-utils.mjs"

/**
 * Returns the local storage mock.
 * @returns {Storage} The local storage mock.
 */
export const getLocalStorageMock = () => {
  let store = {}

  return {
    /**
     * @param {string | number} key
     */
    getItem(key) {
      return store[key]
    },
    /**
     * @param {string | number} key
     * @param {any} value
     */
    setItem(key, value) {
      store[key] = value
    },
    /**
     * @param {string | number} key
     */
    removeItem(key) {
      delete store[key]
    },
    getAll() {
      return { ...store }
    },
    clear() {
      store = {}
    },
    length: Object.keys(store).length,
    key: (/** @type {string | number} */ i) => Object.keys[i]
  }
}

const html =
  `
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

test.beforeEach(() => {
  try {
    const dom = getDom(html)
    const { window } = dom

    // @ts-ignore
    global.window = {
      ...window,
      // @ts-ignore
      matchMedia: query => {
        if (query === "(prefers-color-scheme: dark)") {
          return { 
            matches: true,
            media: query,
            onchange: null,
          }
        }
      }
    }

    global.document = dom.window.document

    global.localStorage = getLocalStorageMock()
    global.localStorage.setItem("color-theme", "light")
  } catch (error) {
    console.error(error)
  }
})

test("Browser switch to Dark mode when light mode was selected", t => {
  setStartupTheme()
  t.is(global.localStorage.getItem("color-theme"), "dark")
})