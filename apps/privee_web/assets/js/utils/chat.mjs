/**
 * Chat screen controller: renders the Signal-encrypted conversation.
 *
 * Server-rendered stream entries (`[data-signal-message]`) carry ciphertext only.
 * Outgoing messages are shown from the local history or the pending outbox
 * (never decrypted), incoming ones are decrypted in ascending `seq` order.
 * All plaintext reaches the DOM as text nodes (`textContent` or the DOM-only
 * markdown renderer), never as HTML.
 */

import {
  DeviceNotReadyError,
  IdentityChangedError,
  NoPeerKeysError,
  wasQueued,
} from "./signal-client.mjs"
import { clientTexts } from "./locale.mjs"
import { openHintEditor } from "./hint-editor.mjs"
import { renderMarkdown } from "./markdown.mjs"
import { hashPassword, historyToCsv, parseCommand, suggestCommands } from "./commands.mjs"
import { VimMode } from "./vim.mjs"

const lockedText = "••••••"

/**
 * @param {Document} doc
 * @returns {Storage | undefined}
 */
const safeLocalStorage = (doc) => {
  try {
    return doc.defaultView?.localStorage
  } catch {
    return undefined
  }
}

export const Selectors = Object.freeze({
  entry: "[data-signal-message]",
  pendingEntry: "[data-signal-message][data-converted=false]",
  banner: "#chat-banner",
  localHistory: "#chat-local-history",
  input: "#chat-text",
  send: "#chat-send",
  safetyNumber: "#chat-safety-number",
  hint: "#chat-hint",
  peerHint: "#chat-peer-hint",
  clearHistory: "#chat-clear-history",
  forgetDevice: "#chat-forget-device",
  exportCsv: "#chat-export",
  commands: "#chat-commands",
  vimIndicator: "#chat-vim-mode",
})

/**
 * @typedef {object} ChatControllerOptions
 * @property {HTMLElement} el The `#chat-screen` element.
 * @property {import("./signal-client.mjs").SignalClient} client
 * @property {number} peerId
 * @property {string} [peerName] Peer session name, stored locally to list the conversation.
 * @property {(message: string) => boolean} [confirm]
 * @property {() => void} [reload]
 * @property {typeof openHintEditor} [editHint]
 * @property {(filename: string, csv: string) => void} [download]
 * @property {Storage} [storage] Where the VIM mode preference is kept.
 */

export class ChatController {
  /** @param {ChatControllerOptions} options */
  constructor({
    el,
    client,
    peerId,
    peerName,
    confirm = (m) => window.confirm(m),
    reload,
    editHint = openHintEditor,
    download,
    storage,
  }) {
    this.el = el
    this.doc = el.ownerDocument
    this.download = download ?? ((filename, csv) => this.downloadFile(filename, csv))
    this.storage = storage ?? safeLocalStorage(this.doc)
    /** @type {{salt: Uint8Array, hash: string} | null} Lock password hash, in memory only. */
    this.lock = null
    /** @type {VimMode | null} */
    this.vim = null
    this.client = client
    this.peerId = peerId
    this.peerName = peerName
    this.confirm = confirm
    this.editHint = editHint
    this.reload = reload ?? (() => this.doc.defaultView?.location.reload())
    /** @type {import("./signal-client.mjs").DeviceState | "starting"} */
    this.state = "starting"
    this.blockedByIdentity = false
    /** @type {Promise<void>} Serializes DOM processing. */
    this.queue = Promise.resolve()
    /** @type {Array<() => void>} */
    this.cleanups = []
    /** @type {Promise<void>} Pending banner rendering. */
    this.bannerTask = Promise.resolve()
  }

  /** @param {string} selector */
  query(selector) {
    return /** @type {HTMLElement | null} */ (this.doc.querySelector(selector))
  }

  get texts() {
    return clientTexts(this.doc)
  }

  /**
   * @param {HTMLElement} entry
   * @param {string} key
   */
  placeholder(entry, key) {
    entry.dataset.clientText = key
    return this.texts[key]
  }

  /** Initializes keys, delivers pending messages and renders the conversation. */
  async start() {
    this.bindComposer()
    this.bindMenu()
    await this.loadPeerMeta()

    try {
      this.setState(await this.client.ensureKeys())
    } catch (e) {
      console.error("Unable to initialize encryption", e)
      this.showBanner("error", this.texts.failedToStart)
      return
    }

    await this.refresh()
    await this.renderLocalHistory()
    this.scrollToEnd()
    if (this.state === "ready") await this.flush()
  }

  /** Stops listening to DOM events. */
  destroy() {
    for (const cleanup of this.cleanups.splice(0)) cleanup()
    this.vim?.destroy()
    this.vim = null
  }

  /**
   * @param {import("./signal-client.mjs").DeviceState} state
   */
  setState(state) {
    this.state = state
    this.updateComposer()

    if (state === "superseded")
      this.showBanner("superseded", this.texts.superseded, this.resetAction())
    else if (state === "needs_reset")
      this.showBanner("needs_reset", this.texts.needsReset, this.resetAction())
    else if (state === "ready") this.clearBanner(["superseded", "needs_reset"])
  }

  updateComposer() {
    const enabled = this.state === "ready" && !this.blockedByIdentity
    const input = /** @type {HTMLInputElement | null} */ (this.query(Selectors.input))
    const send = /** @type {HTMLButtonElement | null} */ (this.query(Selectors.send))
    if (input) input.disabled = !enabled
    if (send) send.disabled = !enabled
  }

  // -- Rendering ---------------------------------------------------------------

  /**
   * Catches up with messages missed since the last visit, then renders the
   * pending stream entries.
   * @returns {Promise<void>}
   */
  refresh() {
    return this.enqueue(async () => {
      const entries = this.pendingEntries()
      const epoch = this.el.dataset.epoch
      if (epoch && !this.blockedByIdentity) {
        const first = /** @type {HTMLElement | null} */ (this.doc.querySelector(Selectors.entry))
        const until = first ? Number(first.dataset.seq) : null
        try {
          await this.client.catchUp(this.peerId, epoch, until)
        } catch (e) {
          this.handleError(e)
        }
      }
      await this.renderEntries(entries)
    })
  }

  /** Renders stream entries added by LiveView. */
  processEntries() {
    return this.enqueue(() => this.renderEntries(this.pendingEntries()))
  }

  /**
   * @param {() => Promise<void>} task
   * @returns {Promise<void>}
   */
  enqueue(task) {
    this.queue = this.queue.then(task).catch((e) => console.error("Chat rendering failed", e))
    return this.queue
  }

  /** @returns {HTMLElement[]} Unrendered entries, ascending by seq. */
  pendingEntries() {
    return /** @type {HTMLElement[]} */ ([...this.doc.querySelectorAll(Selectors.pendingEntry)])
      .filter((el) => el.dataset.converted === "false")
      .sort((a, b) => Number(a.dataset.seq) - Number(b.dataset.seq))
  }

  /** @param {HTMLElement[]} entries */
  async renderEntries(entries) {
    let rendered = false
    for (const entry of entries) {
      if (entry.dataset.converted !== "false") continue
      if (this.blockedByIdentity && entry.dataset.direction === "in") break
      const text = await this.textFor(entry)
      if (text === undefined) break
      this.fill(entry, text)
      rendered = true
    }
    await this.bannerTask
    if (rendered) this.scrollToEnd()
  }

  /**
   * @param {HTMLElement} entry
   * @returns {Promise<string | undefined>} `undefined` when rendering must stop.
   */
  async textFor(entry) {
    const { id, seq, epoch, type, body, direction, clientNonce } = entry.dataset
    if (!id) return this.placeholder(entry, "undecryptable")

    if (direction === "out") {
      // The outbox is checked before the history: the send reply moves the row
      // between them in one transaction, so the opposite order could miss it.
      const row = clientNonce
        ? await this.client.acknowledge(clientNonce, { id, seq: Number(seq), epoch: String(epoch) })
        : await this.client.historyEntry(id)
      return row?.plaintext ?? this.placeholder(entry, "unavailable")
    }

    try {
      const plaintext = await this.client.decryptMessage(this.peerId, {
        id,
        seq: Number(seq),
        epoch: String(epoch),
        type: Number(type),
        body: String(body),
        direction: "in",
      })
      return plaintext ?? this.placeholder(entry, "undecryptable")
    } catch (e) {
      this.handleError(e)
      return undefined
    }
  }

  /**
   * @param {HTMLElement} entry
   * @param {string} text
   */
  fill(entry, text) {
    if (this.lock) {
      entry.textContent = entry.dataset.body || lockedText
      entry.dataset.locked = "true"
    } else {
      entry.replaceChildren(renderMarkdown(this.doc, text))
      delete entry.dataset.locked
    }
    entry.dataset.converted = "true"
    entry.classList.remove("hidden")
  }

  /** Renders local history older than the server window ("Earlier on this device"). */
  async renderLocalHistory() {
    const container = this.query(Selectors.localHistory)
    if (!container) return

    const onScreen = new Set(
      [...this.doc.querySelectorAll(Selectors.entry)].map(
        (el) => /** @type {HTMLElement} */ (el).dataset.id,
      ),
    )
    const first = /** @type {HTMLElement | null} */ (this.doc.querySelector(Selectors.entry))
    const firstTs = first ? await this.firstTimestamp(first) : Infinity

    const rows = (await this.client.history(this.peerId)).filter(
      (row) => !onScreen.has(row.id) && row.ts < firstTs,
    )

    container.replaceChildren()
    if (rows.length === 0) return

    const heading = this.doc.createElement("p")
    heading.className = "py-2 text-center text-xs text-zinc-500"
    heading.dataset.clientText = "earlier"
    heading.textContent = this.texts.earlier
    container.append(heading)
    for (const row of rows) container.append(this.bubble(row))
  }

  /**
   * @param {HTMLElement} first First server-rendered entry.
   * @returns {Promise<number>}
   */
  async firstTimestamp(first) {
    const id = first.dataset.id
    const cached = id ? await this.client.historyEntry(id) : undefined
    return cached?.ts ?? Infinity
  }

  /**
   * @param {import("./signal-client.mjs").HistoryRow} row
   * @returns {HTMLElement}
   */
  bubble(row) {
    const out = row.direction === "out"
    const wrapper = this.doc.createElement("div")
    wrapper.className = `chat ${out ? "chat-end" : "chat-start"}`
    wrapper.dataset.localHistory = row.id

    const bubble = this.doc.createElement("div")
    bubble.className = `chat-bubble opacity-80 ${out ? "chat-bubble-neutral" : "chat-bubble-primary"}`

    const text = this.doc.createElement("p")
    text.className = `text-sm text-left break-word w-max max-w-[calc(100vw-62px)] sm:max-w-[450px] font-normal ${
      out ? "text-zinc-50" : "text-zinc-900"
    }`
    if (this.lock) text.textContent = lockedText
    else if (row.plaintext === null || row.plaintext === undefined)
      text.textContent = this.placeholder(text, out ? "unavailable" : "undecryptable")
    else text.append(renderMarkdown(this.doc, row.plaintext))

    bubble.append(text)
    wrapper.append(bubble)
    return wrapper
  }

  scrollToEnd() {
    this.el.scrollTop = this.el.scrollHeight
  }

  // -- Sending -------------------------------------------------------------------

  bindComposer() {
    const input = /** @type {HTMLInputElement | null} */ (this.query(Selectors.input))
    const send = this.query(Selectors.send)

    if (input && !this.vim) {
      this.vim = new VimMode(input, {
        indicator: this.query(Selectors.vimIndicator),
        storage: this.storage,
      })
    }

    /** @param {KeyboardEvent} event */
    const onKey = (event) => {
      if (event.key === "Tab" && this.completeCommand()) {
        event.preventDefault()
      } else if (event.key === "Escape") {
        this.renderSuggestions([])
      } else if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
        event.preventDefault()
        this.sendFromComposer()
      }
    }
    const onInput = () => this.renderSuggestions(suggestCommands(input?.value ?? ""))
    const onClick = () => this.sendFromComposer()

    input?.addEventListener("keydown", onKey)
    input?.addEventListener("input", onInput)
    send?.addEventListener("click", onClick)
    this.cleanups.push(() => {
      input?.removeEventListener("keydown", onKey)
      input?.removeEventListener("input", onInput)
      send?.removeEventListener("click", onClick)
    })
  }

  /**
   * Shows the commands matching what the user is typing after `:`.
   * @param {readonly import("./commands.mjs").Command[]} commands
   */
  renderSuggestions(commands) {
    const list = this.query(Selectors.commands)
    if (!list) return
    list.replaceChildren()
    list.hidden = commands.length === 0

    for (const command of commands) {
      const item = this.doc.createElement("li")
      const button = this.doc.createElement("button")
      button.type = "button"
      button.dataset.command = command.name
      button.className =
        "flex w-full gap-3 rounded-md px-3 py-1.5 text-left text-sm transition hover:bg-zinc-100 dark:hover:bg-zinc-800"

      const name = this.doc.createElement("span")
      name.className = "font-mono font-semibold"
      name.textContent = `:${command.name}${command.arg ? " …" : ""}`
      const description = this.doc.createElement("span")
      description.className = "text-zinc-500"
      description.dataset.clientText = command.textKey
      description.textContent = this.texts[command.textKey]

      button.append(name, description)
      button.addEventListener("click", () => this.completeCommand(command.name))
      item.append(button)
      list.append(item)
    }
  }

  /**
   * Completes the command being typed (the first suggestion by default).
   * @param {string} [name]
   * @returns {boolean} Whether a command was completed.
   */
  completeCommand(name) {
    const input = /** @type {HTMLInputElement | null} */ (this.query(Selectors.input))
    if (!input) return false
    const command = name ?? suggestCommands(input.value)[0]?.name
    if (!command) return false
    input.value = `:${command} `
    input.focus()
    input.setSelectionRange(input.value.length, input.value.length)
    this.renderSuggestions([])
    return true
  }

  async sendFromComposer() {
    const input = /** @type {HTMLInputElement | null} */ (this.query(Selectors.input))
    if (!input || input.disabled) return
    const text = input.value.trim()
    if (!text) return

    this.renderSuggestions([])
    const command = parseCommand(text)
    if (command) {
      input.value = ""
      await this.runCommand(command.name, command.arg)
      return
    }

    input.value = ""
    try {
      await this.client.send(this.peerId, text)
      this.clearBanner(["notice"])
    } catch (e) {
      const queued = wasQueued(e)
      if (!queued && !input.value) input.value = text
      if (e instanceof NoPeerKeysError) {
        this.showBanner("notice", this.texts.noPeerKeys)
      } else if (!this.handleError(e)) {
        this.showBanner("notice", queued ? this.texts.sendQueued : this.texts.sendFailed)
        console.error("Unable to send message", e)
      }
    }
    await this.processEntries()
  }

  /** Delivers queued messages (after reload, reconnect or new peer keys). */
  async flush() {
    try {
      await this.client.flushOutbox(this.peerId)
    } catch (e) {
      if (!this.handleError(e) && !(e instanceof NoPeerKeysError)) {
        console.warn("Unable to deliver pending messages", e)
      }
    }
    await this.processEntries()
  }

  // -- Server events ---------------------------------------------------------------

  /** The peer published new keys. */
  onPeerKeysReady() {
    if (this.state === "ready") this.flush()
  }

  /** The server asks for more one-time prekeys. */
  async onReplenish() {
    try {
      this.setState(await this.client.replenish())
    } catch (e) {
      console.warn("Unable to replenish prekeys", e)
    }
  }

  /**
   * Another device published a new identity for this session.
   * @param {{identity_key?: string}} payload
   */
  async onIdentitySuperseded(payload) {
    if (payload?.identity_key && payload.identity_key !== (await this.client.identityKey())) {
      this.setState(await this.client.setDeviceState("superseded"))
    }
  }

  // -- Errors and banners ---------------------------------------------------------------

  /**
   * @param {unknown} e
   * @returns {boolean} Whether the error was handled.
   */
  handleError(e) {
    if (e instanceof IdentityChangedError) {
      this.blockedByIdentity = true
      this.updateComposer()
      this.bannerTask = this.showIdentityChanged()
      return true
    }
    if (e instanceof DeviceNotReadyError) {
      if (e.state === "superseded" || e.state === "needs_reset") this.setState(e.state)
      return true
    }
    return false
  }

  async showIdentityChanged() {
    const number = await this.client.safetyNumber(this.peerId)
    this.showBanner(
      "identity",
      this.texts.identityChanged,
      { label: this.texts.acceptIdentity, run: () => this.approveIdentity() },
      number,
    )
  }

  async approveIdentity() {
    await this.client.approveIdentity(this.peerId)
    this.blockedByIdentity = false
    this.clearBanner(["identity"])
    this.updateComposer()
    await this.refresh()
    await this.flush()
  }

  /** @returns {{label: string, run: () => Promise<void>}} */
  resetAction() {
    return {
      label: this.texts.resetIdentity,
      run: async () => {
        if (!this.confirm(this.texts.confirmReset)) return
        try {
          this.setState(await this.client.resetIdentity())
          await this.flush()
        } catch (e) {
          console.error("Unable to reset identity", e)
          this.showBanner("error", this.texts.failedToStart)
        }
      },
    }
  }

  /**
   * @param {string} kind
   * @param {string} message
   * @param {{label: string, run: () => Promise<void> | void}} [action]
   * @param {string | null} [safetyNumber]
   */
  showBanner(kind, message, action, safetyNumber) {
    const container = this.query(Selectors.banner)
    if (!container) return
    this.clearBanner([kind])

    const banner = this.doc.createElement("div")
    banner.id = `chat-banner-${kind}`
    banner.dataset.banner = kind
    banner.setAttribute("role", "alert")
    banner.className =
      "my-2 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900 shadow-sm transition dark:border-amber-700 dark:bg-amber-950 dark:text-amber-100"

    const text = this.doc.createElement("p")
    text.textContent = message
    text.dataset.clientText = Object.keys(this.texts).find((key) => this.texts[key] === message)
    banner.append(text)

    if (safetyNumber) banner.append(this.safetyNumberElement(safetyNumber))

    if (action) {
      const button = this.doc.createElement("button")
      button.type = "button"
      button.id = `chat-banner-${kind}-action`
      button.className =
        "mt-2 rounded-md bg-amber-900 px-3 py-1 text-xs font-semibold text-amber-50 transition hover:bg-amber-700 active:scale-95 dark:bg-amber-100 dark:text-amber-900"
      button.textContent = action.label
      button.dataset.clientText = Object.keys(this.texts).find(
        (key) => this.texts[key] === action.label,
      )
      button.addEventListener("click", () => action.run())
      banner.append(button)
    }

    container.append(banner)
  }

  /** @param {string[]} kinds */
  clearBanner(kinds) {
    for (const kind of kinds) this.doc.getElementById(`chat-banner-${kind}`)?.remove()
  }

  /**
   * @param {string} number 60 digits.
   * @returns {HTMLElement}
   */
  safetyNumberElement(number) {
    const el = this.doc.createElement("p")
    el.className = "mt-2 font-mono tracking-wider"
    el.textContent = (number.match(/.{1,5}/g) || []).join(" ")
    return el
  }

  // -- Menu -------------------------------------------------------------------------

  bindMenu() {
    /**
     * @param {string} selector
     * @param {() => Promise<void>} handler
     */
    const bind = (selector, handler) => {
      const el = this.query(selector)
      if (!el) return
      const listener = () => {
        handler().catch((e) => console.error(e))
      }
      el.addEventListener("click", listener)
      this.cleanups.push(() => el.removeEventListener("click", listener))
    }

    bind(Selectors.safetyNumber, () => this.showSafetyNumber())
    bind(Selectors.hint, () => this.editPeerHint())
    bind(Selectors.clearHistory, () => this.clearHistory())
    bind(Selectors.forgetDevice, () => this.forgetDevice())
    bind(Selectors.exportCsv, () => this.exportCsv())
  }

  // -- Commands (run locally, never sent) -------------------------------------------

  /**
   * @param {import("./commands.mjs").CommandName} name
   * @param {string} arg
   */
  async runCommand(name, arg) {
    try {
      switch (name) {
        case "lock":
          return await this.lockMessages(arg)
        case "unlock":
          return await this.unlockMessages(arg)
        case "export":
          return await this.exportCsv()
        case "safety":
          return await this.showSafetyNumber()
        case "hint":
          return await this.editPeerHint()
        case "clear":
          return await this.clearHistory()
        case "vim":
          this.vim?.toggle()
          return
      }
    } catch (e) {
      console.error(`Command :${name} failed`, e)
    }
  }

  /**
   * Hides the decrypted messages behind a password (#72). Messages stay
   * readable in the local history; the screen shows their ciphertext instead.
   * @param {string} password
   */
  async lockMessages(password) {
    if (!password) {
      this.showBanner("notice", this.texts.lockNeedsPassword)
      return
    }
    this.lock = await hashPassword(password)
    this.el.dataset.locked = "true"
    this.showBanner("locked", this.texts.messagesLocked)
    for (const entry of /** @type {NodeListOf<HTMLElement>} */ (
      this.doc.querySelectorAll(`${Selectors.entry}[data-converted=true]`)
    )) {
      entry.textContent = entry.dataset.body || lockedText
      entry.dataset.locked = "true"
    }
    await this.renderLocalHistory()
  }

  /** @param {string} password */
  async unlockMessages(password) {
    if (!this.lock) return
    const { hash } = await hashPassword(password, this.lock.salt)
    if (hash !== this.lock.hash) {
      this.showBanner("notice", this.texts.wrongPassword)
      return
    }

    this.lock = null
    delete this.el.dataset.locked
    this.clearBanner(["locked", "notice"])
    for (const entry of /** @type {NodeListOf<HTMLElement>} */ (
      this.doc.querySelectorAll(`${Selectors.entry}[data-locked=true]`)
    )) {
      const row = entry.dataset.id ? await this.client.historyEntry(entry.dataset.id) : undefined
      const text =
        row?.plaintext ??
        this.placeholder(entry, entry.dataset.direction === "out" ? "unavailable" : "undecryptable")
      this.fill(entry, text)
    }
    await this.renderLocalHistory()
  }

  /** Downloads the history stored on this device as CSV (#57). */
  async exportCsv() {
    const rows = await this.client.history(this.peerId)
    const date = new Date().toISOString().slice(0, 10)
    const peer = (this.peerName ?? String(this.peerId)).replace(/[^\w.-]+/g, "_")
    this.download(`privee-${peer}-${date}.csv`, historyToCsv(rows))
  }

  /**
   * @param {string} filename
   * @param {string} csv
   */
  downloadFile(filename, csv) {
    const view = this.doc.defaultView
    if (!view) return
    const url = view.URL.createObjectURL(new view.Blob([csv], { type: "text/csv;charset=utf-8" }))
    const link = this.doc.createElement("a")
    link.href = url
    link.download = filename
    link.hidden = true
    this.doc.body.append(link)
    link.click()
    link.remove()
    view.setTimeout(() => view.URL.revokeObjectURL(url), 0)
  }

  // -- Local hint (never sent to the server) -------------------------------------

  /** Lists the conversation on this browser and shows its hint. */
  async loadPeerMeta() {
    try {
      if (this.peerName) await this.client.setPeerName(this.peerId, this.peerName)
      this.renderPeerHint(await this.client.peerHint(this.peerId))
    } catch (e) {
      console.warn("Unable to load the local conversation data", e)
    }
  }

  /** @param {string | null} hint */
  renderPeerHint(hint) {
    const container = this.query(Selectors.peerHint)
    if (!container) return
    container.replaceChildren()
    if (!hint) return

    const text = this.doc.createElement("p")
    text.id = "chat-peer-hint-text"
    text.className = "truncate text-xs italic text-zinc-500 dark:text-zinc-400"
    text.textContent = hint
    container.append(text)
  }

  async editPeerHint() {
    const current = await this.client.peerHint(this.peerId)
    const result = await this.editHint(this.doc, { current })
    if (!result) return
    const hint = await this.client.setPeerHint(
      this.peerId,
      result.action === "save" ? result.hint : null,
    )
    this.renderPeerHint(hint)
  }

  async showSafetyNumber() {
    const number = await this.client.safetyNumber(this.peerId)
    if (!number) {
      this.showBanner("safety", this.texts.exchangeFirst)
      return
    }
    this.showBanner(
      "safety",
      this.texts.compareSafety,
      { label: this.texts.close, run: () => this.clearBanner(["safety"]) },
      number,
    )
  }

  async clearHistory() {
    if (!this.confirm(this.texts.confirmClear)) return
    await this.client.clearHistory(this.peerId)
    this.query(Selectors.localHistory)?.replaceChildren()
  }

  async forgetDevice() {
    if (!this.confirm(this.texts.confirmForget)) return
    await this.client.forgetDevice()
    this.reload()
  }
}
