/**
 * Chat screen controller: renders the Signal-encrypted conversation.
 *
 * Server-rendered stream entries (`[data-signal-message]`) carry ciphertext only.
 * Outgoing messages are shown from the local history or the pending outbox
 * (never decrypted), incoming ones are decrypted in ascending `seq` order.
 * All plaintext reaches the DOM through `textContent`.
 */

import { DeviceNotReadyError, IdentityChangedError, NoPeerKeysError } from "./signal-client.mjs"

export const Selectors = Object.freeze({
  entry: "[data-signal-message]",
  pendingEntry: "[data-signal-message][data-converted=false]",
  banner: "#chat-banner",
  localHistory: "#chat-local-history",
  input: "#chat-text",
  send: "#chat-send",
  safetyNumber: "#chat-safety-number",
  clearHistory: "#chat-clear-history",
  forgetDevice: "#chat-forget-device",
})

export const Texts = Object.freeze({
  undecryptable: "This message could not be decrypted.",
  unavailable: "Sent from another device.",
  noPeerKeys: "Your contact has not set up encryption yet. Try again once they are online.",
  sendFailed: "The message could not be sent. Please try again.",
  identityChanged:
    "Your contact's security code changed. They may have reset their device, or someone may be intercepting the conversation. Verify the safety number with them before continuing.",
  superseded:
    "Encryption for this session was reset on another device, so this device can no longer send or receive messages.",
  needsReset:
    "This device has no encryption keys for this session. Reset the encryption identity to continue; messages sent to your previous device will not be readable here.",
  unsupported:
    "This browser does not support the features required for end-to-end encryption (Web Locks). Please use an up-to-date browser.",
  failedToStart: "Encryption could not be initialized. Please reload the page.",
  earlier: "Earlier on this device",
  confirmClear: "Delete the local history of this conversation from this device?",
  confirmForget:
    "Delete all encryption keys and history of this session from this device? You will need to reset encryption to chat again.",
  confirmReset:
    "Reset the encryption identity of this session? Your contacts will be asked to verify your new safety number.",
})

/**
 * @typedef {object} ChatControllerOptions
 * @property {HTMLElement} el The `#chat-screen` element.
 * @property {import("./signal-client.mjs").SignalClient} client
 * @property {number} peerId
 * @property {(message: string) => boolean} [confirm]
 * @property {() => void} [reload]
 */

export class ChatController {
  /** @param {ChatControllerOptions} options */
  constructor({ el, client, peerId, confirm = (m) => window.confirm(m), reload }) {
    this.el = el
    this.doc = el.ownerDocument
    this.client = client
    this.peerId = peerId
    this.confirm = confirm
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

  /** Initializes keys, delivers pending messages and renders the conversation. */
  async start() {
    this.bindComposer()
    this.bindMenu()

    try {
      this.setState(await this.client.ensureKeys())
    } catch (e) {
      console.error("Unable to initialize encryption", e)
      this.showBanner("error", Texts.failedToStart)
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
  }

  /**
   * @param {import("./signal-client.mjs").DeviceState} state
   */
  setState(state) {
    this.state = state
    this.updateComposer()

    if (state === "superseded") this.showBanner("superseded", Texts.superseded, this.resetAction())
    else if (state === "needs_reset")
      this.showBanner("needs_reset", Texts.needsReset, this.resetAction())
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
    for (const entry of entries) {
      if (entry.dataset.converted !== "false") continue
      if (this.blockedByIdentity && entry.dataset.direction === "in") break
      const text = await this.textFor(entry)
      if (text === undefined) break
      this.fill(entry, text)
    }
    await this.bannerTask
    this.scrollToEnd()
  }

  /**
   * @param {HTMLElement} entry
   * @returns {Promise<string | undefined>} `undefined` when rendering must stop.
   */
  async textFor(entry) {
    const { id, seq, epoch, type, body, direction, clientNonce } = entry.dataset
    if (!id) return Texts.undecryptable

    if (direction === "out") {
      const cached = await this.client.historyEntry(id)
      if (cached) return cached.plaintext ?? Texts.unavailable
      if (clientNonce && (await this.client.outboxEntry(clientNonce))) {
        const row = await this.client.acknowledge(clientNonce, {
          id,
          seq: Number(seq),
          epoch: String(epoch),
        })
        return row?.plaintext ?? Texts.unavailable
      }
      return Texts.unavailable
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
      return plaintext ?? Texts.undecryptable
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
    entry.textContent = text
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
    heading.textContent = Texts.earlier
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
    text.textContent = row.plaintext ?? (out ? Texts.unavailable : Texts.undecryptable)

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

    /** @param {KeyboardEvent} event */
    const onKey = (event) => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
        event.preventDefault()
        this.sendFromComposer()
      }
    }
    const onClick = () => this.sendFromComposer()

    input?.addEventListener("keydown", onKey)
    send?.addEventListener("click", onClick)
    this.cleanups.push(() => {
      input?.removeEventListener("keydown", onKey)
      send?.removeEventListener("click", onClick)
    })
  }

  async sendFromComposer() {
    const input = /** @type {HTMLInputElement | null} */ (this.query(Selectors.input))
    if (!input || input.disabled) return
    const text = input.value.trim()
    if (!text) return

    input.value = ""
    try {
      await this.client.send(this.peerId, text)
      this.clearBanner(["notice"])
    } catch (e) {
      if (e instanceof NoPeerKeysError) {
        input.value = text
        this.showBanner("notice", Texts.noPeerKeys)
      } else if (!this.handleError(e)) {
        this.showBanner("notice", Texts.sendFailed)
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
      Texts.identityChanged,
      { label: "Accept new security code", run: () => this.approveIdentity() },
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
      label: "Reset encryption identity",
      run: async () => {
        if (!this.confirm(Texts.confirmReset)) return
        try {
          this.setState(await this.client.resetIdentity())
          await this.flush()
        } catch (e) {
          console.error("Unable to reset identity", e)
          this.showBanner("error", Texts.failedToStart)
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
    banner.append(text)

    if (safetyNumber) banner.append(this.safetyNumberElement(safetyNumber))

    if (action) {
      const button = this.doc.createElement("button")
      button.type = "button"
      button.id = `chat-banner-${kind}-action`
      button.className =
        "mt-2 rounded-md bg-amber-900 px-3 py-1 text-xs font-semibold text-amber-50 transition hover:bg-amber-700 active:scale-95 dark:bg-amber-100 dark:text-amber-900"
      button.textContent = action.label
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
    bind(Selectors.clearHistory, () => this.clearHistory())
    bind(Selectors.forgetDevice, () => this.forgetDevice())
  }

  async showSafetyNumber() {
    const number = await this.client.safetyNumber(this.peerId)
    if (!number) {
      this.showBanner("safety", "Exchange a message first to compare safety numbers.")
      return
    }
    this.showBanner(
      "safety",
      "Compare this number with your contact, in person or over another channel. If it matches, the conversation is end-to-end encrypted.",
      { label: "Close", run: () => this.clearBanner(["safety"]) },
      number,
    )
  }

  async clearHistory() {
    if (!this.confirm(Texts.confirmClear)) return
    await this.client.clearHistory(this.peerId)
    this.query(Selectors.localHistory)?.replaceChildren()
  }

  async forgetDevice() {
    if (!this.confirm(Texts.confirmForget)) return
    await this.client.forgetDevice()
    this.reload()
  }
}
