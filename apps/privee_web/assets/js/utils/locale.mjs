import { addDarkModeToggleHandlers } from "./dark-mode-switcher.mjs"

export const supportedLocales = Object.freeze(["en", "it", "pt-PT", "es", "fr"])
const cookieName = "privee_locale"

/** @param {Document} [doc] */
export const currentLocale = (doc = document) => {
  const value = doc.cookie
    .split("; ")
    .find((entry) => entry.startsWith(`${cookieName}=`))
    ?.slice(cookieName.length + 1)
  return value && supportedLocales.includes(value) ? value : "en"
}

/**
 * Read application-owned strings delivered by the server's Gettext backend.
 * @param {Document} [doc]
 * @returns {Record<string, string>}
 */
export const clientTexts = (doc = document) => {
  const data = doc.getElementById("language-settings")?.dataset.texts
  if (!data) throw new Error("Missing Gettext client presentation")
  return JSON.parse(data)
}

/**
 * @param {string} key
 * @param {Document} [doc]
 */
export const clientText = (key, doc = document) => {
  const text = clientTexts(doc)[key]
  if (typeof text !== "string") throw new Error(`Missing client translation: ${key}`)
  return text
}

/**
 * Update only nodes explicitly marked as application-owned text, never messages.
 * @param {Document} doc
 */
export const refreshClientTexts = (doc) => {
  const texts = clientTexts(doc)
  for (const el of doc.querySelectorAll("[data-client-text]")) {
    const key = /** @type {HTMLElement} */ (el).dataset.clientText
    if (key && typeof texts[key] === "string") el.textContent = texts[key]
  }
  for (const el of doc.querySelectorAll("[data-client-placeholder]")) {
    const key = /** @type {HTMLElement} */ (el).dataset.clientPlaceholder
    if (key && texts[key]) el.setAttribute("placeholder", texts[key])
  }
  for (const el of doc.querySelectorAll("[data-client-label]")) {
    const key = /** @type {HTMLElement} */ (el).dataset.clientLabel
    if (key && texts[key]) el.setAttribute("aria-label", texts[key])
  }
}

/** @param {any} Hooks */
export const addLocaleHook = (Hooks) => {
  Hooks.Locale = {
    /** @this {any} */
    mounted() {
      addDarkModeToggleHandlers()
      this.handleEvent("locale_changed", (/** @type {{locale: string}} */ { locale }) => {
        if (!supportedLocales.includes(locale)) return
        try {
          document.cookie = `${cookieName}=${locale}; Path=/; Max-Age=31536000; SameSite=Lax${
            location.protocol === "https:" ? "; Secure" : ""
          }`
          if (currentLocale() !== locale) this.pushEvent("locale_persistence_failed", {})
        } catch (error) {
          console.error("Could not persist the language preference", error)
          this.pushEvent("locale_persistence_failed", {})
        }
      })
      this.updatePresentation()
    },
    /** @this {any} */
    updated() {
      this.updatePresentation()
    },
    /** @this {any} */
    updatePresentation() {
      const { locale, description, titleSuffix } = this.el.dataset
      document.documentElement.lang = locale
      document.querySelector("meta[name=description]")?.setAttribute("content", description)
      const title = document.querySelector("title")
      if (title) {
        title.dataset.suffix = ` · ${titleSuffix}`
        title.textContent = `Privee · ${titleSuffix}`
      }
      refreshClientTexts(document)
    },
  }
}
