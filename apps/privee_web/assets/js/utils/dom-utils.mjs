/**
 * Returns an array of HTML elements identified by the given selector.
 * @param {string} selector The query selector.
 */
export const querySelectorArrayOf = (selector) => {
  const elements = []
  document.querySelectorAll(selector).forEach(e => elements.push(e))
  return elements
}
