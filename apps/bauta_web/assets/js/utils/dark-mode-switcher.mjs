const localStorageDarkModeKey = "phx:theme"
const darkModeLabel = "dark"
const lightModelLabel = "light"

// prettier-ignore
const darkIndicatorDataSelector = "[data-theme-selector=\"dark\"]"
// prettier-ignore
const lightIndicatorDataSelector = "[data-theme-selector=\"light\"]"
// prettier-ignore
const themeToggleButtonDataThemeToggle = "[data-theme-toggle=\"theme-toggle\"]"

/**
 * Determines whether the local storage is avaialble or not.
 * @returns {boolean} `True` if the `localStorage` is available, `False` otherwise.
 */
const isLocalStorageAvailable = () =>
  Boolean(
    localStorage &&
    typeof localStorage.getItem === "function" &&
    typeof localStorage.setItem === "function",
  )

/**
 * Gets the setting value for the dark theme from the local storage.
 * @returns {?boolean} `True` if the setting from the local storage determines that the dark theme should be enabled,
 * `False` if not, and `null` if the setting does not exist.
 */
const getDarkThemeSettingFromLocalStorage = () => {
  if (isLocalStorageAvailable()) {
    const value = localStorage.getItem(localStorageDarkModeKey)

    if (value === darkModeLabel) return true
    if (value === lightModelLabel) return false

    // If not explicitly set, use system preference
    return window.matchMedia("(prefers-color-scheme: dark)").matches
  } else {
    return false
  }
}

/**
 * Determines whether the dark mode is enabled for the application or not.
 * @returns {boolean} `True` if the dark mode is enabled, `False` otherwise.
 */
const isDarkModeEnabled = () => getDarkThemeSettingFromLocalStorage() ?? false

/**
 * Removes all the items from the document.
 * @param {NodeListOf<Element>} [items] The item to be removed.
 */
const removeItems = (items) => {
  if (!items) return

  items.forEach((item) => item.classList.add("hidden"))
}

/**
 * Re-add all the items from the document.
 * @param {NodeListOf<Element>} [items] The item to be re-added.
 */
const reAddItems = (items) => {
  if (!items) return

  items.forEach((item) => item.classList.remove("hidden"))
}

/**
 * Tries to set the theme for the page.
 * @param {"dark"|"light"|"system"} theme The selected theme.
 */
const trySetTheme = (theme) => {
  if (isLocalStorageAvailable()) {
    if (theme === "system") {
      localStorage.removeItem(localStorageDarkModeKey)
    } else {
      localStorage.setItem(localStorageDarkModeKey, theme)
    }
  }

  const themeToggleDarkSelectors = document.querySelectorAll(darkIndicatorDataSelector)
  const themeToggleLightSelectors = document.querySelectorAll(lightIndicatorDataSelector)

  if (theme === darkModeLabel) {
    removeItems(themeToggleDarkSelectors)
    reAddItems(themeToggleLightSelectors)

    // Set the phx standard data-theme attribute
    document.documentElement.setAttribute("data-theme", darkModeLabel)
  } else if (theme === lightModelLabel) {
    removeItems(themeToggleLightSelectors)
    reAddItems(themeToggleDarkSelectors)

    document.documentElement.setAttribute("data-theme", lightModelLabel)
  } else {
    // system: remove explicit theme attribute
    removeItems(themeToggleLightSelectors)
    reAddItems(themeToggleDarkSelectors)

    document.documentElement.removeAttribute("data-theme")
  }
}

/**
 * Sets the theme at startup.
 */
export const setStartupTheme = () =>
  trySetTheme(isDarkModeEnabled() ? darkModeLabel : lightModelLabel)

/**
 * Adds all the handlers to toggle the Dark mode theme in the page,
 * and sets initial theme state.
 */
export const addToggleDarkModeHandling = () => {
  setStartupTheme()
  addDarkModeToggleHandlers()
}

/**
 * Adds the handlers for the buttons that toggle the dark mode theme.
 */
export const addDarkModeToggleHandlers = () => {
  const themeToggleButtons = document.querySelectorAll(themeToggleButtonDataThemeToggle)

  themeToggleButtons.forEach((themeToggleButton) => {
    themeToggleButton.removeEventListener("click", themeToggleHandler)
    themeToggleButton.addEventListener("click", themeToggleHandler)
  })
}

/**
 * Handles the theme toggle. Not inlined because it has to be removed before
 * being re-added again to avoid duplications.
 */
const themeToggleHandler = () => {
  if (isDarkModeEnabled()) {
    trySetTheme(lightModelLabel)
  } else {
    trySetTheme(darkModeLabel)
  }
}
