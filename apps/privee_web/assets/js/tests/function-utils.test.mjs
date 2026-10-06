/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { debounce, throttle, once, memoize, delay } from "../utils/function-utils.mjs"

describe("Function Utilities", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  describe("debounce", () => {
    it("should delay function execution", () => {
      const fn = vi.fn()
      const debouncedFn = debounce(fn, 100)

      debouncedFn()
      expect(fn).not.toHaveBeenCalled()

      vi.advanceTimersByTime(100)
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should reset timer on repeated calls", () => {
      const fn = vi.fn()
      const debouncedFn = debounce(fn, 100)

      debouncedFn()
      vi.advanceTimersByTime(50)
      debouncedFn()
      vi.advanceTimersByTime(50)

      // Should not have fired yet (timer was reset)
      expect(fn).not.toHaveBeenCalled()

      vi.advanceTimersByTime(50)
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should pass arguments correctly", () => {
      const fn = vi.fn()
      const debouncedFn = debounce(fn, 100)

      debouncedFn("arg1", "arg2")
      vi.advanceTimersByTime(100)

      expect(fn).toHaveBeenCalledWith("arg1", "arg2")
    })

    it("should only execute once for rapid calls", () => {
      const fn = vi.fn()
      const debouncedFn = debounce(fn, 100)

      // Rapid fire 10 calls
      for (let i = 0; i < 10; i++) {
        debouncedFn()
      }

      vi.advanceTimersByTime(100)
      expect(fn).toHaveBeenCalledTimes(1)
    })
  })

  describe("throttle", () => {
    it("should limit function execution rate", () => {
      const fn = vi.fn()
      const throttledFn = throttle(fn, 100)

      throttledFn()
      expect(fn).toHaveBeenCalledTimes(1)

      throttledFn()
      throttledFn()
      expect(fn).toHaveBeenCalledTimes(1) // Still 1

      vi.advanceTimersByTime(100)
      expect(fn).toHaveBeenCalledTimes(2) // Now 2
    })

    it("should execute immediately on first call", () => {
      const fn = vi.fn()
      const throttledFn = throttle(fn, 100)

      throttledFn()
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should pass latest arguments", () => {
      const fn = vi.fn()
      const throttledFn = throttle(fn, 100)

      throttledFn("arg1")
      throttledFn("arg2")
      throttledFn("arg3")

      expect(fn).toHaveBeenCalledWith("arg1")

      vi.advanceTimersByTime(100)
      expect(fn).toHaveBeenCalledWith("arg3")
    })

    it("should allow execution after delay period", () => {
      const fn = vi.fn()
      const throttledFn = throttle(fn, 100)

      throttledFn()
      expect(fn).toHaveBeenCalledTimes(1)

      vi.advanceTimersByTime(100)
      throttledFn()
      expect(fn).toHaveBeenCalledTimes(2)
    })
  })

  describe("once", () => {
    it("should execute function only once", () => {
      const fn = vi.fn(() => "result")
      const onceFn = once(fn)

      onceFn()
      onceFn()
      onceFn()

      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should return the same result on subsequent calls", () => {
      const fn = vi.fn(() => "result")
      const onceFn = once(fn)

      const result1 = onceFn()
      const result2 = onceFn()
      const result3 = onceFn()

      expect(result1).toBe("result")
      expect(result2).toBe("result")
      expect(result3).toBe("result")
    })

    it("should pass arguments to function", () => {
      const fn = vi.fn((a, b) => a + b)
      const onceFn = once(fn)

      const result = onceFn(2, 3)
      expect(result).toBe(5)
      expect(fn).toHaveBeenCalledWith(2, 3)
    })

    it("should ignore arguments on subsequent calls", () => {
      const fn = vi.fn((x) => x * 2)
      const onceFn = once(fn)

      const result1 = onceFn(5) // 10
      const result2 = onceFn(10) // Still 10 (from first call)

      expect(result1).toBe(10)
      expect(result2).toBe(10)
      expect(fn).toHaveBeenCalledTimes(1)
    })
  })

  describe("memoize", () => {
    it("should cache function results", () => {
      const fn = vi.fn((x) => x * 2)
      const memoizedFn = memoize(fn)

      memoizedFn(5)
      memoizedFn(5)
      memoizedFn(5)

      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should return cached result", () => {
      const fn = vi.fn((x) => x * 2)
      const memoizedFn = memoize(fn)

      const result1 = memoizedFn(5)
      const result2 = memoizedFn(5)

      expect(result1).toBe(10)
      expect(result2).toBe(10)
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it("should compute for different arguments", () => {
      const fn = vi.fn((x) => x * 2)
      const memoizedFn = memoize(fn)

      memoizedFn(5)
      memoizedFn(10)
      memoizedFn(5) // Cached

      expect(fn).toHaveBeenCalledTimes(2)
    })

    it("should handle multiple arguments", () => {
      const fn = vi.fn((a, b) => a + b)
      const memoizedFn = memoize(fn)

      const result1 = memoizedFn(2, 3)
      const result2 = memoizedFn(2, 3)

      expect(result1).toBe(5)
      expect(result2).toBe(5)
      expect(fn).toHaveBeenCalledTimes(1)
    })
  })

  describe("delay", () => {
    it("should delay function execution", async () => {
      const fn = vi.fn(() => "result")
      const delayedFn = delay(fn, 100)

      const promise = delayedFn()
      expect(fn).not.toHaveBeenCalled()

      vi.advanceTimersByTime(100)
      const result = await promise

      expect(fn).toHaveBeenCalledTimes(1)
      expect(result).toBe("result")
    })

    it("should pass arguments correctly", async () => {
      const fn = vi.fn((a, b) => a + b)
      const delayedFn = delay(fn, 100)

      const promise = delayedFn(2, 3)
      vi.advanceTimersByTime(100)
      const result = await promise

      expect(result).toBe(5)
      expect(fn).toHaveBeenCalledWith(2, 3)
    })

    it("should return a promise", () => {
      const fn = vi.fn()
      const delayedFn = delay(fn, 100)

      const result = delayedFn()
      expect(result).toBeInstanceOf(Promise)
    })
  })

  describe("Real-world usage patterns", () => {
    it("should debounce search input", () => {
      const searchAPI = vi.fn()
      const debouncedSearch = debounce(searchAPI, 300)

      // User types "hello" quickly
      debouncedSearch("h")
      vi.advanceTimersByTime(50)
      debouncedSearch("he")
      vi.advanceTimersByTime(50)
      debouncedSearch("hel")
      vi.advanceTimersByTime(50)
      debouncedSearch("hell")
      vi.advanceTimersByTime(50)
      debouncedSearch("hello")

      // Should not have called API yet
      expect(searchAPI).not.toHaveBeenCalled()

      // User stops typing for 300ms
      vi.advanceTimersByTime(300)

      // Now API should be called once with final value
      expect(searchAPI).toHaveBeenCalledTimes(1)
      expect(searchAPI).toHaveBeenCalledWith("hello")
    })

    it("should throttle scroll handler", () => {
      const updateScrollPosition = vi.fn()
      const throttledScroll = throttle(updateScrollPosition, 100)

      // Simulate rapid scrolling
      for (let i = 0; i < 10; i++) {
        throttledScroll()
      }

      // Should fire immediately once
      expect(updateScrollPosition).toHaveBeenCalledTimes(1)

      vi.advanceTimersByTime(100)

      // Should fire once more after throttle period
      expect(updateScrollPosition).toHaveBeenCalledTimes(2)
    })

    it("should initialize app once", () => {
      const setupEventListeners = vi.fn()
      const initializeApp = once(setupEventListeners)

      // Multiple initialization attempts
      initializeApp()
      initializeApp()
      initializeApp()

      // Should only set up once
      expect(setupEventListeners).toHaveBeenCalledTimes(1)
    })

    it("should memoize expensive calculations", () => {
      const expensiveCalculation = vi.fn((n) => {
        let result = 0
        for (let i = 0; i < n; i++) {
          result += i
        }
        return result
      })

      const memoizedCalc = memoize(expensiveCalculation)

      memoizedCalc(1000)
      memoizedCalc(1000)
      memoizedCalc(1000)

      // Should only calculate once
      expect(expensiveCalculation).toHaveBeenCalledTimes(1)
    })
  })
})
