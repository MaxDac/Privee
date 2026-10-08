/**
 * Removes the local conversation hints of the session before the sign-out
 * link is followed (phoenix_html handles its `data-method="delete"`).
 */

import { clearHintsOnSignOut } from "./peer-hints.mjs"

/**
 * @param {Document} [doc]
 * @param {(ownId: string) => Promise<void>} [clearHints]
 * @returns {() => void} Removes the listener.
 */
export const addSignOutHintsCleanup = (doc = document, clearHints = clearHintsOnSignOut) => {
  /** @param {Event} event */
  const listener = (event) => {
    const target = /** @type {Element | null} */ (event.target)
    const link = /** @type {HTMLElement | null} */ (
      typeof target?.closest === "function" ? target.closest("#log-out-link") : null
    )
    if (!link || link.dataset.hintsCleared === "true") return
    const ownId = link.dataset.ownSessionId
    if (!ownId) return

    event.preventDefault()
    event.stopImmediatePropagation()
    clearHints(ownId)
      .catch((e) => console.warn("Unable to clear local hints", e))
      .finally(() => {
        link.dataset.hintsCleared = "true"
        link.click()
      })
  }
  doc.addEventListener("click", listener, true)
  return () => doc.removeEventListener("click", listener, true)
}
