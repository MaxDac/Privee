// Creating a mock for localStorage
export const localStorageMock = (() => {
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
})

export const windowMock = {
  innerWidth: 1024,
  location: {
    href: "https://example.com",
  },
  addEventListener: () => {},
  removeEventListener: () => {},
  matchMedia: (/** @type {string} */ media) => {
    if (media === "(prefers-color-scheme: dark)") {
      return { 
        matches: true,
        media: media,
        onchange: null,
      }
    }
  },
  // Add other properties/methods as needed
}

// TODO - Fill mock
export const documentMock = {
  getElementById: _id => {
    return {
      classList: {
        add: () => {},
        remove: () => {},
      },
    }
  },
  classList: {
    add: () => {},
    remove: () => {},
  },
}