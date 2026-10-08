import { JSDOM } from "jsdom"
import { describe, it, expect, vi } from "vitest"
import { currentLocale, refreshClientTexts, addLocaleHook } from "../utils/locale.mjs"
import { installCatalog, catalogTexts } from "./gettext-fixture.mjs"

describe("browser language presentation", () => {
  it("reports a browser refusing preference persistence", () => {
    const dom = new JSDOM("", { url: "https://example.com" })
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("location", dom.window.location)
    const el = installCatalog(dom.window.document)
    Object.defineProperty(dom.window.document, "cookie", {
      get: () => "",
      set: () => {},
    })
    const hooks = {}
    addLocaleHook(hooks)
    const events = {}
    const hook = {
      ...hooks.Locale,
      el,
      handleEvent: (name, fn) => {
        events[name] = fn
      },
      pushEvent: vi.fn(),
    }
    hook.mounted()
    events.locale_changed({ locale: "it" })
    expect(hook.pushEvent).toHaveBeenCalledWith("locale_persistence_failed", {})
    vi.unstubAllGlobals()
  })
  it("defaults English and rejects unsupported cookie values", () => {
    const doc = new JSDOM("", { url: "https://example.com" }).window.document
    expect(currentLocale(doc)).toBe("en")
    doc.cookie = "privee_locale=xx"
    expect(currentLocale(doc)).toBe("en")
    for (const locale of ["en", "it", "pt-PT", "es", "fr"]) {
      doc.cookie = `privee_locale=${locale}`
      expect(currentLocale(doc)).toBe(locale)
    }
  })

  it("updates only presentation, preserving input values, disabled state and user text", () => {
    const doc = new JSDOM(`
      <input id="draft" value="private draft" data-client-placeholder="messagePlaceholder">
      <p id="message">This message could not be decrypted.</p>
      <p id="placeholder" data-client-text="undecryptable"></p>
      <button id="action" data-client-text="resetIdentity"></button>
    `).window.document
    const input = doc.getElementById("draft")
    const message = doc.getElementById("message")
    installCatalog(doc, "it")
    refreshClientTexts(doc)
    expect(input.value).toBe("private draft")
    expect(input.disabled).toBe(false)
    expect(input.placeholder).toBe(catalogTexts("it").messagePlaceholder)
    expect(message.textContent).toBe("This message could not be decrypted.")
    expect(doc.getElementById("placeholder").textContent).toBe(catalogTexts("it").undecryptable)
    expect(doc.getElementById("action").textContent).toBe(catalogTexts("it").resetIdentity)
  })

  it("saves only an allowlisted cookie and updates document presentation without navigation", () => {
    const dom = new JSDOM(
      "<head><title>Privee</title><meta name='description'></head><body></body>",
      {
        url: "https://example.com/login",
      },
    )
    vi.stubGlobal("document", dom.window.document)
    vi.stubGlobal("location", dom.window.location)
    vi.stubGlobal("localStorage", dom.window.localStorage)
    const el = installCatalog(dom.window.document, "fr")
    el.dataset.description = "Description française"
    el.dataset.titleSuffix = "Application de confidentialité"
    const hooks = {}
    addLocaleHook(hooks)
    const events = {}
    const hook = {
      ...hooks.Locale,
      el,
      handleEvent: (name, fn) => {
        events[name] = fn
      },
      pushEvent: vi.fn(),
    }
    hook.mounted()
    events.locale_changed({ locale: "fr" })
    expect(currentLocale()).toBe("fr")
    expect(document.documentElement.lang).toBe("fr")
    expect(document.title).toBe("Privee · Application de confidentialité")
    expect(dom.window.location.pathname).toBe("/login")
    events.locale_changed({ locale: "../invalid" })
    expect(currentLocale()).toBe("fr")
    vi.unstubAllGlobals()
  })
})
