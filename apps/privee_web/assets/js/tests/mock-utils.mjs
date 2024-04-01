import { JSDOM } from "jsdom"

/**
 * Returns an already configured JSDOM instance.
 * @param {string} html The HTML content. It is defaulted to an empty string.
 * @returns {JSDOM} The JSDOM instance.
 */
export const getDom = (html = "") =>
  new JSDOM(html, {
    // Defining the url is necessary to avoid errors with the localStorage.
    // For more information, refer the following issue:
    // https://github.com/jsdom/jsdom/issues/2383#issuecomment-442199291
    url: "http://localhost",
  })

/**
 * Mocks the Notification object.
 */
export class NotificationMock {
  /**
   * Build a new Notification mock.
   * @param {string} title
   * @param {NotificationOptions} params
   */
  constructor(title, params) {
    this.title = title
    this.body = params.body
    this.icon = params.icon
  }

  /**
   * Adds a new event listener
   * @param {string} type
   * @param {Function} callback
   */
  addEventListener(type, callback) {
    if (type === "click") {
      callback()
    }
  }
}

/**
 * Returns a random string.
 * @returns {string} A random string.
 */
export const generateRandomString = () => Math.random().toString(36).substring(7)
