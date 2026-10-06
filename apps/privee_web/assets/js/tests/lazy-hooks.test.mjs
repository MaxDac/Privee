import { describe, it, expect, vi } from "vitest"
import { createLazyHook } from "../utils/lazy-hooks.mjs"

describe("createLazyHook", () => {
  const moduleWith = (/** @type {Record<string, any>} */ impl) =>
    Promise.resolve({ addHooks: (/** @type {any} */ Hooks) => (Hooks.Test = impl) })

  it("forwards lifecycle callbacks to the loaded hook", async () => {
    const impl = { mounted: vi.fn(), updated: vi.fn(), destroyed: vi.fn() }
    /** @type {any} */
    const hook = createLazyHook(() => moduleWith(impl), "addHooks", "Test")

    await hook.mounted()
    hook.updated()
    hook.destroyed()
    expect(impl.mounted).toHaveBeenCalledOnce()
    expect(impl.updated).toHaveBeenCalledOnce()
    expect(impl.destroyed).toHaveBeenCalledOnce()
  })

  it("does not clash with LiveView's internal hook members", async () => {
    const impl = { mounted: vi.fn(), destroyed: vi.fn() }
    const lifecycle = { __destroyed() {}, __mounted() {} }
    // LiveView binds hook callbacks to a ViewHook that has `__`-prefixed internals.
    /** @type {any} */
    const hook = Object.assign(
      Object.create(lifecycle),
      createLazyHook(() => moduleWith(impl), "addHooks", "Test"),
    )

    await hook.mounted()
    hook.destroyed()
    expect(impl.mounted).toHaveBeenCalledOnce()
    expect(impl.destroyed).toHaveBeenCalledOnce()
    expect(hook.__destroyed).toBe(lifecycle.__destroyed)
  })

  it("does not mount a hook destroyed while loading", async () => {
    const impl = { mounted: vi.fn(), destroyed: vi.fn() }
    /** @type {any} */
    const hook = createLazyHook(() => moduleWith(impl), "addHooks", "Test")

    const mounting = hook.mounted()
    hook.destroyed()
    await mounting
    expect(impl.mounted).not.toHaveBeenCalled()
  })

  it("mounts on LiveView hook instances, which define a __destroyed method", async () => {
    const impl = { mounted: vi.fn() }
    /** @type {any} */
    const hook = Object.assign(
      Object.create({ __destroyed() {} }),
      createLazyHook(() => moduleWith(impl), "addHooks", "Test"),
    )

    await hook.mounted()
    expect(impl.mounted).toHaveBeenCalledOnce()
  })
})
