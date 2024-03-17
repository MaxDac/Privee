const localStorageDarkModeKey = "color-theme"
const darkModeLabel = "dark"
const lightModelLabel = "light"

const darkIndicatorDataSelector = "[data-theme-selector=\"dark\"]"
const lightIndicatorDataSelector = "[data-theme-selector=\"light\"]"
const themeToggleButtonDataThemeToggle = "[data-theme-toggle=\"theme-toggle\"]"

/**
  * Determines whether the local storage is avaialble or not.
  * @returns {boolean} `True` if the `localStorage` is available, `False` otherwise.
  */
const isLocalStorageAvailable = () =>
  Boolean(localStorage && localStorage.getItem && localStorage.setItem)

/**
  * Gets the setting value for the dark theme from the local storage.
  * @returns {?boolean} `True` if the setting from the local storage determines that the dark theme should be enabled,
  * `False` if not, and `null` if the setting does not exist.
  */
const getDarkThemeSettingFromLocalStorage = () => {
  if (isLocalStorageAvailable()) {
    return localStorage.getItem(localStorageDarkModeKey) === darkModeLabel || 
      (!(localStorageDarkModeKey in localStorage) && window.matchMedia("(prefers-color-scheme: dark)").matches)
  } else {
    return false
  }
}

/**
  * Determines whether the dark mode is enabled for the application or not.
  * @returns {boolean} `True` if the dark mode is enabled, `False` otherwise.
  */
const isDarkModeEnabled = () => {
  const settingValue = getDarkThemeSettingFromLocalStorage()

  if (settingValue == null) {
    return true
  }

  return settingValue
}

/**
 * Removes all the items from the document.
 * @param {NodeListOf<Element>} [items] The item to be removed.
 */
const removeItems = items => items.forEach(item => item.classList.add("hidden"))

/**
 * Re-add all the items from the document.
 * @param {NodeListOf<Element>} [items] The item to be re-added.
 */
const reAddItems = items => items.forEach(item => item.classList.remove("hidden"))

/**
  * Tries to set the theme for the page.
  * @param {"dark"|"light"} theme The selected theme.
  */
const trySetTheme = (theme) => {
  if (isLocalStorageAvailable()) {
    localStorage.setItem(localStorageDarkModeKey, theme)
  }

  const themeToggleDarkSelectors = document.querySelectorAll(darkIndicatorDataSelector)
  const themeToggleLightSelectors = document.querySelectorAll(lightIndicatorDataSelector)

  if (theme === darkModeLabel) {
    removeItems(themeToggleDarkSelectors)
    reAddItems(themeToggleLightSelectors)

    document.documentElement.classList.remove(lightModelLabel)
    document.documentElement.classList.add(darkModeLabel)
  } else {
    removeItems(themeToggleLightSelectors)
    reAddItems(themeToggleDarkSelectors)

    document.documentElement.classList.remove(darkModeLabel)
    document.documentElement.classList.add(lightModelLabel)
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

  const themeToggleButtons = 
    document.querySelectorAll(themeToggleButtonDataThemeToggle)

  themeToggleButtons.forEach(themeToggleButton => {
    themeToggleButton.addEventListener("click", () => {
      if (isDarkModeEnabled()) {
        trySetTheme(lightModelLabel)
      } else {
        trySetTheme(darkModeLabel)
      }
    })
  })
}
