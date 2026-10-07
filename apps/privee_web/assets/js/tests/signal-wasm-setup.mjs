/**
 * Instantiates libsignal synchronously from the served binary, so
 * `SignalClient.open` never fetches it.
 */

import { readFileSync } from "node:fs"
import { initSync } from "../../vendor/libsignal-wasm/libsignal_wasm.js"

initSync({
  module: readFileSync(
    new URL("../../../priv/static/wasm/libsignal_wasm_bg.wasm", import.meta.url),
  ),
})
