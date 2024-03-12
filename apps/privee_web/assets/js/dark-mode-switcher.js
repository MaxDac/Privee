const localStorageDarkModeKey = "color-theme"
const darkModeLabel = "dark"
const lightModelLabel = "light"

const darkIconId = "theme-toggle-dark-icon"
const lightIconId = "theme-toggle-light-icon"
const themeToggleButtonId = "theme-toggle"

/**
  * Determines whether the local storage is avaialble or not.
  * @returns {bool} `True` if the `localStorage` is available, `False` otherwise.
  */
const isLocalStorageAvailable = () =>
  localStorage && localStorage.getItem && localStorage.setItem

/**
  * Gets the setting value for the dark theme from the local storage.
  * @returns {?bool} `True` if the setting from the local storage determines that the dark theme should be enabled,
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
  * @returns {bool} `True` if the dark mode is enabled, `False` otherwise.
  */
const isDarkModeEnabled = () => {
  const settingValue = getDarkThemeSettingFromLocalStorage()

  if (settingValue == null) {
    return true
  }

  return settingValue
};

/**
  * Tries to set the theme for the page.
  * @param {"dark"|"light"} The selected theme.
  */
const trySetTheme = (theme) => {
  if (isLocalStorageAvailable()) {
    localStorage.setItem(localStorageDarkModeKey, theme)
  }

  const themeToggleDarkIcon = document.getElementById(darkIconId)
  const themeToggleLightIcon = document.getElementById(lightIconId)

  if (theme === darkModeLabel) {
    themeToggleDarkIcon.classList.add("hidden")
    themeToggleLightIcon.classList.remove("hidden")

    document.documentElement.classList.remove(lightModelLabel)
    document.documentElement.classList.add(darkModeLabel)
  } else {
    themeToggleDarkIcon.classList.remove("hidden")
    themeToggleLightIcon.classList.add("hidden")

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
  console.debug("invoking dark mode handling")
  setStartupTheme()

  const themeToggleButton = document.getElementById(themeToggleButtonId)

  themeToggleButton.addEventListener("click", () => {
    console.debug("toggling")

    if (isDarkModeEnabled()) {
      trySetTheme(lightModelLabel)
    } else {
      trySetTheme(darkModeLabel)
    }
  })
}
