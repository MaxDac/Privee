# libsignal-wasm (vendored)

WebAssembly build of the official [libsignal](https://github.com/signalapp/libsignal)
protocol crate (tag `v0.86.5`), produced by
[`MaxDac/libsignal-wasm`](https://github.com/MaxDac/libsignal-wasm) (`@maxdac/libsignal-wasm`
0.86.5).

- `libsignal_wasm.js` / `libsignal_wasm.d.ts`: wasm-bindgen glue (`--target web`), bundled by esbuild.
- The binary lives in `apps/privee_web/priv/static/wasm/libsignal_wasm_bg.wasm` and is fetched
  lazily by `js/utils/signal-wasm.mjs` when a page opens the Signal client.

To update, build the package (`scripts/build.sh` in libsignal-wasm) or download the release
tarball, then copy `pkg/libsignal_wasm.{js,d.ts}` here and `pkg/libsignal_wasm_bg.wasm` to
`priv/static/wasm/`, and bump `WASM_VERSION` in `js/utils/signal-wasm.mjs`.
