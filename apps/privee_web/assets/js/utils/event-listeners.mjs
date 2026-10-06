/**
 * Event listener utilities for optimal performance.
 * This module provides helper functions for adding event listeners
 * with proper performance optimizations.
 */

/**
 * Adds a passive event listener for scroll, touch, or wheel events.
 * Passive listeners improve scrolling performance by telling the browser
 * that the handler won't call preventDefault(), allowing non-blocking scrolling.
 *
 * @param {EventTarget} element - The element to attach the listener to
 * @param {string} eventType - The event type (e.g., 'scroll', 'touchstart', 'wheel')
 * @param {EventListener} handler - The event handler function
 * @returns {Function} A function to remove the event listener
 *
 * @example
 * // Add passive scroll listener
 * const removeListener = addPassiveListener(window, 'scroll', (e) => {
 *   console.log('Scrolled to:', window.scrollY)
 * })
 *
 * // Later, remove it
 * removeListener()
 */
export const addPassiveListener = (element, eventType, handler) => {
  element.addEventListener(eventType, handler, { passive: true })

  // Return cleanup function
  return () => element.removeEventListener(eventType, handler)
}

/**
 * Adds a throttled passive event listener.
 * Combines passive listeners with throttling for high-frequency events.
 * Useful for scroll, resize, or mousemove events that fire rapidly.
 *
 * @param {EventTarget} element - The element to attach the listener to
 * @param {string} eventType - The event type
 * @param {EventListener} handler - The event handler function
 * @param {number} delay - Minimum time between handler calls in milliseconds (default: 100ms)
 * @returns {Function} A function to remove the event listener
 *
 * @example
 * // Scroll handler that only fires every 100ms at most
 * const removeListener = addThrottledPassiveListener(window, 'scroll', (e) => {
 *   updateScrollIndicator()
 * }, 100)
 */
export const addThrottledPassiveListener = (element, eventType, handler, delay = 100) => {
  let lastCall = 0
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timeoutId

  /** @param {Event} event */
  const throttledHandler = (event) => {
    const now = Date.now()
    const timeSinceLastCall = now - lastCall

    if (timeSinceLastCall >= delay) {
      lastCall = now
      handler(event)
    } else {
      // Schedule the call for when the delay period is over
      if (timeoutId !== undefined) {
        clearTimeout(timeoutId)
      }
      timeoutId = setTimeout(() => {
        lastCall = Date.now()
        handler(event)
      }, delay - timeSinceLastCall)
    }
  }

  element.addEventListener(eventType, throttledHandler, { passive: true })

  // Return cleanup function
  return () => {
    if (timeoutId) {
      clearTimeout(timeoutId)
    }
    element.removeEventListener(eventType, throttledHandler)
  }
}

/**
 * Adds a debounced passive event listener.
 * Waits for the event to stop firing for the specified delay before calling the handler.
 * Useful for events like resize or scroll where you only care about the final state.
 *
 * @param {EventTarget} element - The element to attach the listener to
 * @param {string} eventType - The event type
 * @param {EventListener} handler - The event handler function
 * @param {number} delay - Time to wait after last event before calling handler (default: 200ms)
 * @returns {Function} A function to remove the event listener
 *
 * @example
 * // Only update layout after user stops scrolling for 200ms
 * const removeListener = addDebouncedPassiveListener(window, 'scroll', (e) => {
 *   recalculateLayout()
 * }, 200)
 */
export const addDebouncedPassiveListener = (element, eventType, handler, delay = 200) => {
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timeoutId

  /** @param {Event} event */
  const debouncedHandler = (event) => {
    if (timeoutId) {
      clearTimeout(timeoutId)
    }

    timeoutId = setTimeout(() => {
      handler(event)
    }, delay)
  }

  element.addEventListener(eventType, debouncedHandler, { passive: true })

  // Return cleanup function
  return () => {
    if (timeoutId) {
      clearTimeout(timeoutId)
    }
    element.removeEventListener(eventType, debouncedHandler)
  }
}

/**
 * Helper to check if passive listeners are supported by the browser.
 * @returns {boolean} True if passive listeners are supported
 */
export const supportsPassive = (() => {
  let supported = false

  try {
    const options = {
      get passive() {
        supported = true
        return false
      },
    }

    const testHandler = () => {}
    window.addEventListener("test", testHandler, options)
    window.removeEventListener("test", testHandler)
  } catch {
    supported = false
  }

  return supported
})()

/**
 * Adds an event listener with passive option if supported, otherwise falls back to standard.
 * Use this for maximum browser compatibility.
 *
 * @param {EventTarget} element - The element to attach the listener to
 * @param {string} eventType - The event type
 * @param {EventListener} handler - The event handler function
 * @returns {Function} A function to remove the event listener
 *
 * @example
 * const removeListener = addCompatiblePassiveListener(window, 'touchstart', handler)
 */
export const addCompatiblePassiveListener = (element, eventType, handler) => {
  const options = supportsPassive ? { passive: true } : undefined

  element.addEventListener(eventType, handler, options)

  // Return cleanup function
  return () => element.removeEventListener(eventType, handler)
}
