/**
 * A small VIM mode for the chat composer (#63).
 *
 * Normal mode: h l 0 $ w b e x X D C dd cc i a I A, Esc to leave insert mode.
 * Enter sends the message in both modes. The choice is stored per browser.
 */

const storageKey = "privee:vim"

/**
 * @param {Storage | undefined} storage
 * @returns {boolean}
 */
export const vimPreference = (storage) => {
  try {
    return storage?.getItem(storageKey) === "1"
  } catch {
    return false
  }
}

/**
 * @param {Storage | undefined} storage
 * @param {boolean} enabled
 */
const saveVimPreference = (storage, enabled) => {
  try {
    if (enabled) storage?.setItem(storageKey, "1")
    else storage?.removeItem(storageKey)
  } catch {
    // Private browsing may refuse the write; the mode still works for this page.
  }
}

/**
 * @param {string} text
 * @param {number} pos
 */
const nextWord = (text, pos) => {
  let i = pos
  while (i < text.length && !/\s/.test(text[i])) i++
  while (i < text.length && /\s/.test(text[i])) i++
  return i
}

/**
 * @param {string} text
 * @param {number} pos
 */
const previousWord = (text, pos) => {
  let i = pos - 1
  while (i > 0 && /\s/.test(text[i])) i--
  while (i > 0 && !/\s/.test(text[i - 1])) i--
  return Math.max(i, 0)
}

/**
 * @param {string} text
 * @param {number} pos
 */
const wordEnd = (text, pos) => {
  let i = pos + 1
  while (i < text.length && /\s/.test(text[i])) i++
  while (i < text.length - 1 && !/\s/.test(text[i + 1])) i++
  return Math.min(i, Math.max(text.length - 1, 0))
}

export class VimMode {
  /**
   * @param {HTMLInputElement} input
   * @param {{indicator?: HTMLElement | null, storage?: Storage}} [options]
   */
  constructor(input, { indicator = null, storage } = {}) {
    this.input = input
    this.indicator = indicator
    this.storage = storage
    this.enabled = false
    /** @type {"normal" | "insert"} */
    this.mode = "insert"
    /** @type {string | null} Pending operator (`d` or `c`). */
    this.pending = null
    this.onKeyDown = this.onKeyDown.bind(this)
    input.addEventListener("keydown", this.onKeyDown)
    this.setEnabled(vimPreference(storage), { persist: false })
  }

  destroy() {
    this.input.removeEventListener("keydown", this.onKeyDown)
  }

  /** @returns {boolean} The new state. */
  toggle() {
    this.setEnabled(!this.enabled)
    return this.enabled
  }

  /**
   * @param {boolean} enabled
   * @param {{persist?: boolean}} [options]
   */
  setEnabled(enabled, { persist = true } = {}) {
    this.enabled = enabled
    this.mode = "insert"
    this.pending = null
    if (persist) saveVimPreference(this.storage, enabled)
    this.render()
  }

  render() {
    this.input.dataset.vimMode = this.enabled ? this.mode : "off"
    if (!this.indicator) return
    this.indicator.hidden = !this.enabled
    this.indicator.textContent = this.mode === "normal" ? "-- NORMAL --" : "-- INSERT --"
  }

  /** @param {"normal" | "insert"} mode */
  setMode(mode) {
    this.mode = mode
    this.pending = null
    if (mode === "normal") this.moveTo(Math.max((this.input.selectionStart ?? 0) - 1, 0))
    this.render()
  }

  get pos() {
    return this.input.selectionStart ?? 0
  }

  /** @param {number} pos */
  moveTo(pos) {
    const max =
      this.mode === "normal" ? Math.max(this.input.value.length - 1, 0) : this.input.value.length
    const clamped = Math.min(Math.max(pos, 0), max)
    this.input.setSelectionRange(clamped, clamped)
  }

  /**
   * @param {number} start
   * @param {number} end
   */
  remove(start, end) {
    const value = this.input.value
    this.input.value = value.slice(0, start) + value.slice(end)
    this.moveTo(start)
  }

  /** @param {KeyboardEvent} event */
  onKeyDown(event) {
    if (!this.enabled || event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return

    if (this.mode === "insert") {
      if (event.key === "Escape") {
        event.preventDefault()
        this.setMode("normal")
      }
      return
    }

    if (event.key === "Enter" || event.key === "Tab") return
    if (event.key.length === 1 || event.key === "Escape") event.preventDefault()
    if (this.handle(event.key)) event.stopImmediatePropagation()
  }

  /**
   * Applies a normal mode key.
   * @param {string} key
   * @returns {boolean} Whether the key was consumed.
   */
  handle(key) {
    const text = this.input.value
    const pos = this.pos

    if (this.pending) {
      const operator = this.pending
      this.pending = null
      if (key === operator) {
        this.input.value = ""
        this.input.setSelectionRange(0, 0)
        if (operator === "c") this.setMode("insert")
      }
      return true
    }

    switch (key) {
      case "Escape":
        this.pending = null
        return true
      case "h":
        this.moveTo(pos - 1)
        return true
      case "l":
        this.moveTo(pos + 1)
        return true
      case "0":
        this.moveTo(0)
        return true
      case "$":
        this.moveTo(text.length)
        return true
      case "w":
        this.moveTo(nextWord(text, pos))
        return true
      case "b":
        this.moveTo(previousWord(text, pos))
        return true
      case "e":
        this.moveTo(wordEnd(text, pos))
        return true
      case "x":
        this.remove(pos, pos + 1)
        return true
      case "X":
        if (pos > 0) this.remove(pos - 1, pos)
        return true
      case "D":
        this.remove(pos, text.length)
        return true
      case "C":
        this.remove(pos, text.length)
        this.insertAt(pos)
        return true
      case "d":
      case "c":
        this.pending = key
        return true
      case "i":
        this.insertAt(pos)
        return true
      case "a":
        this.insertAt(Math.min(pos + 1, text.length))
        return true
      case "I":
        this.insertAt(0)
        return true
      case "A":
        this.insertAt(text.length)
        return true
      default:
        return key.length === 1
    }
  }

  /** @param {number} pos */
  insertAt(pos) {
    this.mode = "insert"
    this.pending = null
    this.input.setSelectionRange(pos, pos)
    this.render()
  }
}
