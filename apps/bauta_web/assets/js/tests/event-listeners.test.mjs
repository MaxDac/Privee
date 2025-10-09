/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import {
  addPassiveListener,
  addThrottledPassiveListener,
  addDebouncedPassiveListener,
  supportsPassive,
  addCompatiblePassiveListener,
} from "../utils/event-listeners.mjs"

describe("Event Listener Utilities", () => {
  let element
  let handler

  beforeEach(() => {
    element = document.createElement("div")
    handler = vi.fn()
  })

  describe("addPassiveListener", () => {
    it("should add event listener and return cleanup function", () => {
      const removeListener = addPassiveListener(element, "scroll", handler)

      // Trigger event
      element.dispatchEvent(new Event("scroll"))
      expect(handler).toHaveBeenCalledTimes(1)

      // Cleanup
      removeListener()
      element.dispatchEvent(new Event("scroll"))
      expect(handler).toHaveBeenCalledTimes(1) // Should not increase
    })

    it("should work with multiple event types", () => {
      const scrollHandler = vi.fn()
      const touchHandler = vi.fn()

      addPassiveListener(element, "scroll", scrollHandler)
      addPassiveListener(element, "touchstart", touchHandler)

      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("touchstart"))

      expect(scrollHandler).toHaveBeenCalledTimes(1)
      expect(touchHandler).toHaveBeenCalledTimes(1)
    })
  })

  describe("addThrottledPassiveListener", () => {
    beforeEach(() => {
      vi.useFakeTimers()
    })

    afterEach(() => {
      vi.restoreAllMocks()
      vi.useRealTimers()
    })

    it("should throttle rapid events", () => {
      addThrottledPassiveListener(element, "scroll", handler, 100)

      // Fire multiple events rapidly
      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("scroll"))

      // Should only fire once immediately
      expect(handler).toHaveBeenCalledTimes(1)

      // Advance time by 100ms
      vi.advanceTimersByTime(100)

      // Fire more events
      element.dispatchEvent(new Event("scroll"))
      expect(handler).toHaveBeenCalledTimes(2)
    })

    it("should cleanup timers on remove", () => {
      const removeListener = addThrottledPassiveListener(element, "scroll", handler, 100)

      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("scroll"))

      removeListener()

      vi.advanceTimersByTime(100)
      element.dispatchEvent(new Event("scroll"))

      // Should only have been called once (before removal)
      expect(handler).toHaveBeenCalledTimes(1)
    })
  })

  describe("addDebouncedPassiveListener", () => {
    beforeEach(() => {
      vi.useFakeTimers()
    })

    afterEach(() => {
      vi.restoreAllMocks()
      vi.useRealTimers()
    })

    it("should debounce events and only fire after delay", () => {
      addDebouncedPassiveListener(element, "scroll", handler, 200)

      // Fire multiple events rapidly
      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("scroll"))
      element.dispatchEvent(new Event("scroll"))

      // Should not fire yet
      expect(handler).toHaveBeenCalledTimes(0)

      // Advance time by 200ms
      vi.advanceTimersByTime(200)

      // Should fire once after debounce period
      expect(handler).toHaveBeenCalledTimes(1)
    })

    it("should reset timer on new events", () => {
      addDebouncedPassiveListener(element, "scroll", handler, 200)

      element.dispatchEvent(new Event("scroll"))
      vi.advanceTimersByTime(100)

      // Fire another event, should reset timer
      element.dispatchEvent(new Event("scroll"))
      vi.advanceTimersByTime(100)

      // Should not have fired yet (only 100ms since last event)
      expect(handler).toHaveBeenCalledTimes(0)

      // Advance another 100ms (total 200ms since last event)
      vi.advanceTimersByTime(100)
      expect(handler).toHaveBeenCalledTimes(1)
    })

    it("should cleanup timers on remove", () => {
      const removeListener = addDebouncedPassiveListener(element, "scroll", handler, 200)

      element.dispatchEvent(new Event("scroll"))
      removeListener()

      vi.advanceTimersByTime(200)

      // Should not fire after removal
      expect(handler).toHaveBeenCalledTimes(0)
    })
  })

  describe("supportsPassive", () => {
    it("should return a boolean", () => {
      expect(typeof supportsPassive).toBe("boolean")
    })

    it("should detect passive support (modern browsers)", () => {
      // In Vitest/JSDOM environment, passive should be supported
      expect(supportsPassive).toBe(true)
    })
  })

  describe("addCompatiblePassiveListener", () => {
    it("should add event listener with compatibility fallback", () => {
      const removeListener = addCompatiblePassiveListener(element, "scroll", handler)

      element.dispatchEvent(new Event("scroll"))
      expect(handler).toHaveBeenCalledTimes(1)

      removeListener()
      element.dispatchEvent(new Event("scroll"))
      expect(handler).toHaveBeenCalledTimes(1)
    })

    it("should work with touch events", () => {
      addCompatiblePassiveListener(element, "touchstart", handler)

      element.dispatchEvent(new Event("touchstart"))
      expect(handler).toHaveBeenCalledTimes(1)
    })
  })

  describe("Integration: Real-world usage patterns", () => {
    beforeEach(() => {
      vi.useFakeTimers()
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    it("should handle scroll performance pattern", () => {
      const scrollHandler = vi.fn()
      const removeListener = addThrottledPassiveListener(window, "scroll", scrollHandler, 100)

      // Simulate rapid scrolling
      for (let i = 0; i < 10; i++) {
        window.dispatchEvent(new Event("scroll"))
      }

      expect(scrollHandler).toHaveBeenCalledTimes(1)

      vi.advanceTimersByTime(100)
      expect(scrollHandler).toHaveBeenCalledTimes(2)

      removeListener()
    })

    it("should handle resize debounce pattern", () => {
      const resizeHandler = vi.fn()
      const removeListener = addDebouncedPassiveListener(window, "resize", resizeHandler, 250)

      // Simulate window resizing
      for (let i = 0; i < 5; i++) {
        window.dispatchEvent(new Event("resize"))
        vi.advanceTimersByTime(50)
      }

      // Should not fire during resizing
      expect(resizeHandler).toHaveBeenCalledTimes(0)

      // Wait for debounce period after last event
      vi.advanceTimersByTime(250)
      expect(resizeHandler).toHaveBeenCalledTimes(1)

      removeListener()
    })
  })
})
