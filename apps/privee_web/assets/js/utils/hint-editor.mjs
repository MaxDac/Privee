/**
 * Modal editor of a local conversation hint. Every time it opens, it advises
 * not to use the contact's name: anyone with access to the browser can read
 * hints. User text only reaches the DOM through `value`/`textContent`.
 */

import { clientText } from "./locale.mjs"
import { HINT_MAX_LENGTH } from "./peer-hints.mjs"

/** @typedef {{action: "save", hint: string} | {action: "remove"} | null} HintEditorResult */

const BUTTON =
  "rounded-lg px-3 py-1.5 text-sm font-semibold transition active:scale-95 focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"

/**
 * @param {Document} doc
 * @param {string} tag
 * @param {{id?: string, className?: string, textKey?: string}} [options]
 */
const element = (doc, tag, { id, className, textKey } = {}) => {
  const el = doc.createElement(tag)
  if (id) el.id = id
  if (className) el.className = className
  if (textKey) {
    el.dataset.clientText = textKey
    el.textContent = clientText(textKey, doc)
  }
  return el
}

/**
 * Opens the hint editor.
 * @param {Document} doc
 * @param {{current?: string | null}} [options]
 * @returns {Promise<HintEditorResult>} `null` when cancelled.
 */
export const openHintEditor = (doc, { current = null } = {}) => {
  doc.getElementById("hint-editor")?.remove()

  const dialog = /** @type {HTMLDialogElement} */ (
    element(doc, "dialog", {
      id: "hint-editor",
      className:
        "m-auto w-[min(24rem,calc(100vw-2rem))] rounded-2xl border border-zinc-200 bg-white p-5 text-zinc-900 shadow-2xl backdrop:bg-zinc-900/40 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50",
    })
  )
  dialog.setAttribute("aria-labelledby", "hint-editor-title")

  const form = /** @type {HTMLFormElement} */ (
    element(doc, "form", { id: "hint-editor-form", className: "flex flex-col gap-3" })
  )

  const title = element(doc, "h2", {
    id: "hint-editor-title",
    className: "text-base font-semibold",
    textKey: "hintTitle",
  })

  const advice = element(doc, "p", {
    id: "hint-editor-advice",
    className:
      "rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:border-amber-700 dark:bg-amber-950 dark:text-amber-100",
    textKey: "hintAdvice",
  })
  advice.setAttribute("role", "note")

  const label = element(doc, "label", {
    className: "text-sm font-medium",
    textKey: "hintLabel",
  })
  label.setAttribute("for", "hint-editor-input")

  const input = /** @type {HTMLInputElement} */ (
    element(doc, "input", {
      id: "hint-editor-input",
      className:
        "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 focus:border-zinc-500 focus:outline-none dark:border-zinc-600 dark:bg-zinc-800 dark:text-zinc-50",
    })
  )
  input.type = "text"
  input.maxLength = HINT_MAX_LENGTH
  input.autocomplete = "off"
  input.spellcheck = false
  input.value = current ?? ""
  input.setAttribute("aria-describedby", "hint-editor-advice")

  const actions = element(doc, "div", { className: "flex flex-wrap justify-end gap-2 pt-1" })
  const cancel = element(doc, "button", {
    id: "hint-editor-cancel",
    className: `${BUTTON} text-zinc-600 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800`,
    textKey: "cancel",
  })
  cancel.setAttribute("type", "button")
  const save = element(doc, "button", {
    id: "hint-editor-save",
    className: `${BUTTON} bg-zinc-900 text-zinc-50 hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300`,
    textKey: "save",
  })
  save.setAttribute("type", "submit")

  if (current) {
    const remove = element(doc, "button", {
      id: "hint-editor-remove",
      className: `${BUTTON} mr-auto text-red-600 hover:bg-red-50 dark:hover:bg-red-950`,
      textKey: "hintRemove",
    })
    remove.setAttribute("type", "button")
    remove.addEventListener("click", () => finish({ action: "remove" }))
    actions.append(remove)
  }
  actions.append(cancel, save)

  form.append(title, advice, label, input, actions)
  dialog.append(form)
  doc.body.append(dialog)

  /** @type {(result: HintEditorResult) => void} */
  let resolve = () => {}
  const result = /** @type {Promise<HintEditorResult>} */ (new Promise((r) => (resolve = r)))

  /** @param {HintEditorResult} value */
  const finish = (value) => {
    if (dialog.open && typeof dialog.close === "function") dialog.close()
    dialog.remove()
    resolve(value)
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault()
    finish(input.value.trim() ? { action: "save", hint: input.value } : { action: "remove" })
  })
  cancel.addEventListener("click", () => finish(null))
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault()
    finish(null)
  })

  try {
    dialog.showModal()
  } catch {
    dialog.setAttribute("open", "")
  }
  input.focus()

  return result
}
