/**
 * In-memory stand-in for `PriveeWeb.SignalKeysLive` and `PriveeWeb.ChatLive`,
 * reproducing the reply shapes and server-side invariants the client relies on.
 */

export class FakeServer {
  constructor() {
    /** @type {Map<number, any>} */
    this.bundles = new Map()
    this.epochs = new Map()
    /** @type {any[]} */
    this.messages = []
    this.nonces = new Map()
    this.seq = 0
    this.epochCounter = 0
    /** @type {Array<{to: number, event: string, payload: any}>} */
    this.pushed = []
    /** Reply overrides: `event -> (payload) => reply | undefined`. */
    this.intercept = new Map()
  }

  /**
   * @param {number} a
   * @param {number} b
   */
  convKey(a, b) {
    return a < b ? `${a}:${b}` : `${b}:${a}`
  }

  /**
   * @param {number} a
   * @param {number} b
   */
  currentEpoch(a, b) {
    const key = this.convKey(a, b)
    if (!this.epochs.has(key)) this.epochs.set(key, `e${++this.epochCounter}`)
    return this.epochs.get(key)
  }

  /** Simulates a conversation expiry (or a server restart). */
  rotateEpoch(a, b) {
    this.epochs.set(this.convKey(a, b), `e${++this.epochCounter}`)
  }

  /**
   * Returns the push function of session `ownId`, chatting with `peerId`.
   * @param {number} ownId
   * @param {number} [peerId]
   */
  connect(ownId, peerId) {
    return (/** @type {string} */ event, /** @type {any} */ payload = {}) => {
      const override = this.intercept.get(event)?.(payload, ownId)
      if (override !== undefined) return Promise.resolve(override)
      return Promise.resolve(this.handle(ownId, peerId, event, payload))
    }
  }

  /**
   * @param {number} ownId
   * @param {number | undefined} peerId
   * @param {string} event
   * @param {any} p
   */
  handle(ownId, peerId, event, p) {
    const bundle = this.bundles.get(ownId)

    switch (event) {
      case "signal_status": {
        return {
          identity_key: bundle?.identity_key ?? null,
          opk_count: bundle?.one_time_prekeys.length ?? 0,
          max_opk_id: bundle?.max_opk_id ?? 0,
          max_age_ms: 7 * 24 * 3600 * 1000,
        }
      }

      case "publish_identity": {
        if (bundle && bundle.identity_key !== p.identity_key) return { error: "already_published" }
        if (!bundle) this.store(ownId, p)
        return { ok: true }
      }

      case "reset_identity": {
        this.store(ownId, p)
        // Like the real server, end every conversation of the reset session.
        for (const key of this.epochs.keys()) {
          if (key.split(":").includes(String(ownId)))
            this.epochs.set(key, `e${++this.epochCounter}`)
        }
        this.pushed.push({ to: ownId, event: "identity_superseded", payload: p.identity_key })
        return { ok: true }
      }

      case "rotate_signed_prekey": {
        if (!bundle || bundle.identity_key !== p.identity_key) return { error: "identity_mismatch" }
        bundle.signed_prekey = p.signed_prekey
        bundle.kyber_prekey = p.kyber_prekey
        return { ok: true }
      }

      case "add_prekeys": {
        if (!bundle || bundle.identity_key !== p.identity_key) return { error: "identity_mismatch" }
        if (p.one_time_prekeys.some((/** @type {any} */ k) => k.key_id <= bundle.max_opk_id)) {
          return { error: "stale_prekey_ids" }
        }
        bundle.one_time_prekeys.push(...p.one_time_prekeys)
        bundle.max_opk_id = Math.max(
          ...bundle.one_time_prekeys.map((/** @type {any} */ k) => k.key_id),
        )
        return { ok: true }
      }

      case "open_conversation":
        return { epoch: this.currentEpoch(ownId, /** @type {number} */ (peerId)) }

      case "request_peer_bundle": {
        const peer = this.bundles.get(peerId)
        if (!peer) return { error: "not_found" }
        const opk = peer.one_time_prekeys.shift() ?? null
        return {
          peer_id: peerId,
          bundle: {
            identity_key: peer.identity_key,
            registration_id: peer.registration_id,
            signed_prekey: peer.signed_prekey,
            kyber_prekey: peer.kyber_prekey,
            one_time_prekey: opk,
          },
        }
      }

      case "send_message": {
        if (bundle?.identity_key !== p.identity_key) return { error: "superseded" }
        const epoch = this.currentEpoch(ownId, /** @type {number} */ (peerId))
        if (p.epoch !== epoch) return { error: "stale_epoch", epoch }
        const dup = this.nonces.get(`${ownId}:${p.client_nonce}`)
        if (dup) return this.reply(dup)
        const message = {
          id: crypto.randomUUID(),
          seq: ++this.seq,
          epoch,
          from: ownId,
          to: peerId,
          type: p.type,
          body: p.body,
          client_nonce: p.client_nonce,
        }
        this.messages.push(message)
        this.nonces.set(`${ownId}:${p.client_nonce}`, message)
        return this.reply(message)
      }

      case "fetch_messages": {
        const key = this.convKey(ownId, /** @type {number} */ (peerId))
        const all = this.messages.filter(
          (m) => this.convKey(m.from, m.to) === key && m.epoch === p.epoch && m.seq > p.after_seq,
        )
        const page = all.slice(0, this.pageSize ?? 200)
        return {
          messages: page.map((m) => this.serialize(m, ownId)),
          next_cursor: all.length > page.length ? page[page.length - 1].seq : null,
        }
      }

      default:
        return { error: "unknown_event" }
    }
  }

  /**
   * @param {number} ownId
   * @param {any} p
   */
  store(ownId, p) {
    this.bundles.set(ownId, {
      identity_key: p.identity_key,
      registration_id: p.registration_id,
      signed_prekey: p.signed_prekey,
      kyber_prekey: p.kyber_prekey,
      one_time_prekeys: [...p.one_time_prekeys],
      max_opk_id: Math.max(0, ...p.one_time_prekeys.map((/** @type {any} */ k) => k.key_id)),
    })
  }

  /** @param {any} m */
  reply(m) {
    return { id: m.id, seq: m.seq, epoch: m.epoch, client_nonce: m.client_nonce }
  }

  /**
   * Server messages as seen by `viewerId` (stream / fetch serialization).
   * @param {any} m
   * @param {number} viewerId
   */
  serialize(m, viewerId) {
    const out = m.from === viewerId
    return {
      id: m.id,
      seq: m.seq,
      epoch: m.epoch,
      type: m.type,
      body: m.body,
      direction: out ? "out" : "in",
      client_nonce: out ? m.client_nonce : null,
    }
  }

  /**
   * Messages of the conversation visible to `viewerId`.
   * @param {number} viewerId
   * @param {number} peerId
   */
  inbox(viewerId, peerId) {
    return this.messages
      .filter((m) => m.from === peerId && m.to === viewerId)
      .map((m) => this.serialize(m, viewerId))
  }
}
