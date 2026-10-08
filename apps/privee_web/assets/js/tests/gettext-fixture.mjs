import { readFileSync } from "node:fs"

/**
 * Use the real catalogs and server key mapping in client tests, not a second dictionary.
 * @param {string} [locale]
 * @returns {Record<string, string>}
 */
export const catalogTexts = (locale = "en") => {
  const po = readFileSync(
    new URL(`../../../priv/gettext/${locale}/LC_MESSAGES/default.po`, import.meta.url),
    "utf8",
  )
  const entries = new Map(
    [
      ...po
        .replace(/\r\n/g, "\n")
        .matchAll(/^msgid ("(?:[^"\\]|\\.)*")\nmsgstr ("(?:[^"\\]|\\.)*")$/gm),
    ].map(([, id, value]) => [JSON.parse(id), JSON.parse(value)]),
  )
  const source = readFileSync(
    new URL("../../../lib/privee_web/client_texts.ex", import.meta.url),
    "utf8",
  )
  return Object.fromEntries(
    [...source.matchAll(/(\w+):\s*gettext\(\s*("(?:[^"\\]|\\.)*")/g)].map(([, key, id]) => {
      const value = entries.get(JSON.parse(id))
      if (!value) throw new Error(`Missing catalog fixture: ${locale}/${key}`)
      return [key, value]
    }),
  )
}

/**
 * @param {Document} doc
 * @param {string} [locale]
 */
export const installCatalog = (doc, locale = "en") => {
  const el = doc.getElementById("language-settings") ?? doc.createElement("div")
  el.id = "language-settings"
  el.dataset.locale = locale
  el.dataset.texts = JSON.stringify(catalogTexts(locale))
  if (!el.parentNode) doc.body.append(el)
  return el
}
