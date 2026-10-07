/**
 * Loader of the official libsignal compiled to WebAssembly (`vendor/libsignal-wasm`).
 *
 * The ~1 MB binary is served from `priv/static/wasm` and fetched only when a
 * page actually opens the Signal client.
 */

import init, {
  SignalStore as Protocol,
  preKeyMessageIdentity,
} from "../../vendor/libsignal-wasm/libsignal_wasm.js"

export { Protocol, preKeyMessageIdentity }

export const WASM_VERSION = "0.86.5"
export const WASM_URL = `/wasm/libsignal_wasm_bg.wasm?v=${WASM_VERSION}`

/** @type {Promise<void> | undefined} */
let loading

/**
 * Instantiates the WebAssembly module once. A no-op when it was already
 * initialized (for example synchronously by the tests).
 * @param {string | URL} [source]
 * @returns {Promise<void>}
 */
export const loadSignal = (source = WASM_URL) => {
  loading ??= init({ module_or_path: source }).then(
    () => undefined,
    (e) => {
      loading = undefined
      throw e
    },
  )
  return loading
}
