/**
 * Function utilities for performance optimization.
 * This module provides helper functions for controlling function execution frequency.
 */

/**
 * Creates a debounced version of a function.
 * The debounced function will delay executing the provided function until after
 * the specified delay has elapsed since the last time it was invoked.
 *
 * Useful for expensive operations that should only run after user stops performing
 * an action (e.g., API calls after typing stops, layout recalculation after resize stops).
 *
 * @param {Function} fn - The function to debounce
 * @param {number} ms - The delay in milliseconds
 * @returns {Function} A debounced version of the function
 *
 * @example
 * // Search API call only fires 300ms after user stops typing
 * const debouncedSearch = debounce((query) => {
 *   searchAPI(query)
 * }, 300)
 *
 * inputElement.addEventListener('input', (e) => {
 *   debouncedSearch(e.target.value)
 * })
 */
export const debounce = (fn, ms) => {
  let timeoutId
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), ms)
  }
}

/**
 * Creates a throttled version of a function.
 * The throttled function will only execute at most once per specified time period,
 * no matter how many times it's called.
 *
 * Useful for rate-limiting expensive operations that fire frequently
 * (e.g., scroll handlers, resize handlers, mouse move tracking).
 *
 * @param {Function} fn - The function to throttle
 * @param {number} ms - The minimum time between executions in milliseconds
 * @returns {Function} A throttled version of the function
 *
 * @example
 * // Scroll handler only fires every 100ms at most
 * const throttledScroll = throttle(() => {
 *   updateScrollPosition()
 * }, 100)
 *
 * window.addEventListener('scroll', throttledScroll)
 */
export const throttle = (fn, ms) => {
  let lastCall = 0
  let timeoutId = null

  return (...args) => {
    const now = Date.now()
    const timeSinceLastCall = now - lastCall

    if (timeSinceLastCall >= ms) {
      lastCall = now
      fn(...args)
    } else {
      // Schedule the call for when the delay period is over
      if (timeoutId) {
        clearTimeout(timeoutId)
      }
      timeoutId = setTimeout(() => {
        lastCall = Date.now()
        fn(...args)
      }, ms - timeSinceLastCall)
    }
  }
}

/**
 * Creates a function that only executes once.
 * Subsequent calls return the result of the first call.
 *
 * Useful for initialization functions that should only run once
 * (e.g., setting up event listeners, initializing plugins).
 *
 * @param {Function} fn - The function to execute once
 * @returns {Function} A function that only executes once
 *
 * @example
 * const initializeApp = once(() => {
 *   console.log('App initialized')
 *   setupEventListeners()
 * })
 *
 * initializeApp() // Logs and sets up listeners
 * initializeApp() // Does nothing
 * initializeApp() // Does nothing
 */
export const once = (fn) => {
  let result
  let hasRun = false

  return (...args) => {
    if (!hasRun) {
      result = fn(...args)
      hasRun = true
    }
    return result
  }
}

/**
 * Creates a memoized version of a function.
 * Results are cached based on the arguments, so repeated calls with
 * the same arguments return the cached result instead of re-executing.
 *
 * Useful for expensive pure functions (functions that always return the same
 * result for the same inputs).
 *
 * @param {Function} fn - The function to memoize
 * @returns {Function} A memoized version of the function
 *
 * @example
 * const expensiveCalculation = memoize((n) => {
 *   console.log('Computing...')
 *   return n * n * n
 * })
 *
 * expensiveCalculation(5) // Logs 'Computing...' and returns 125
 * expensiveCalculation(5) // Returns 125 immediately from cache
 */
export const memoize = (fn) => {
  const cache = new Map()

  return (...args) => {
    const key = JSON.stringify(args)

    if (cache.has(key)) {
      return cache.get(key)
    }

    const result = fn(...args)
    cache.set(key, result)
    return result
  }
}

/**
 * Delays execution of a function by the specified milliseconds.
 * Returns a promise that resolves with the function's return value.
 *
 * Useful for adding intentional delays or creating animations.
 *
 * @param {Function} fn - The function to delay
 * @param {number} ms - The delay in milliseconds
 * @returns {Function} A function that returns a promise
 *
 * @example
 * const delayedAlert = delay(() => {
 *   alert('This appears after 2 seconds')
 * }, 2000)
 *
 * await delayedAlert()
 */
export const delay = (fn, ms) => {
  return (...args) => {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve(fn(...args))
      }, ms)
    })
  }
}
