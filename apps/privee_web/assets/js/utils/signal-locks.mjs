/**
 * Cross-tab locking for Signal Protocol state.
 *
 * Signal state (ratchets, one-time prekeys, counters) must never be mutated by
 * two tabs at once, so locking is fail-closed: without the Web Locks API the
 * chat refuses to operate instead of falling back to an in-tab mutex.
 */

/**
 * @typedef {object} Locks
 * @property {<T>(name: string, options: {mode?: "shared" | "exclusive"}, fn: () => Promise<T>) => Promise<T>} request
 */

export class UnsupportedBrowserError extends Error {
  constructor() {
    super("This browser does not support the Web Locks API")
    this.name = "UnsupportedBrowserError"
  }
}

/**
 * Returns the Web Locks implementation of `nav`, or throws.
 * @param {any} [nav]
 * @returns {Locks}
 */
export const webLocks = (nav = globalThis.navigator) => {
  const locks = nav?.locks
  if (!locks || typeof locks.request !== "function") throw new UnsupportedBrowserError()

  return {
    request: (name, options, fn) => locks.request(name, options, () => fn()),
  }
}

/**
 * In-realm readers/writer lock with the Web Locks semantics used here.
 * Only for tests: it does not coordinate across tabs.
 * @returns {Locks}
 */
export const createMemoryLocks = () => {
  /** @type {Map<string, {shared: number, exclusive: boolean, queue: Array<{mode: string, start: () => void}>}>} */
  const states = new Map()

  /** @param {string} name */
  const stateOf = (name) => {
    let state = states.get(name)
    if (!state) {
      state = { shared: 0, exclusive: false, queue: [] }
      states.set(name, state)
    }
    return state
  }

  /** @param {string} name */
  const pump = (name) => {
    const state = stateOf(name)
    while (state.queue.length > 0) {
      const next = state.queue[0]
      const canRun =
        next.mode === "shared" ? !state.exclusive : !state.exclusive && state.shared === 0
      if (!canRun) return
      state.queue.shift()
      if (next.mode === "shared") state.shared++
      else state.exclusive = true
      next.start()
    }
  }

  return {
    request(name, options, fn) {
      const mode = options?.mode === "shared" ? "shared" : "exclusive"
      const state = stateOf(name)

      return new Promise((resolve, reject) => {
        state.queue.push({
          mode,
          start: () => {
            Promise.resolve()
              .then(fn)
              .then(resolve, reject)
              .finally(() => {
                if (mode === "shared") state.shared--
                else state.exclusive = false
                pump(name)
              })
          },
        })
        pump(name)
      })
    },
  }
}
