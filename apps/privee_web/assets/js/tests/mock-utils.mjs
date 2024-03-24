import { JSDOM } from "jsdom"

/**
 * Returns an already configured JSDOM instance. 
 * @param {string} html The HTML content. It is defaulted to an empty string.
 * @returns {JSDOM} The JSDOM instance.
 */
export const getDom = (html = "") => new JSDOM(html, {
  // Defining the url is necessary to avoid errors with the localStorage.
  // For more information, consult the following issue:
  // https://github.com/jsdom/jsdom/issues/2383#issuecomment-442199291
  url: "http://localhost",
})