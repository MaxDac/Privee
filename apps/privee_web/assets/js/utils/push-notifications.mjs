/**
 * Determines whether the browser supports notifications, if not it logs it,
 * if it supports it asks for permission to the user and logs the result.
 * @returns {Promise<string>} The result of the permission request.
 */
export const askNotificationPermission = () => {
  if ("Notification" in window) {
    return Notification.requestPermission().then(() => {
      return `Permission: ${Notification.permission === "granted" ? "granted" : "denied"}`
    })
  } else {
    return Promise.reject("This browser does not support notifications.")
  }
}

/**
 * @typedef {Object} EventDetails Represents the details of the event sent from the back end. For more information read `events.ex` file.
 * @property {string} [text] The text of the message that triggered the notification.
 * @property {string} [session_name] The session name that sent the message.
 * @property {boolean} [check_focus] Whether to check if the window is in focus before triggering the notification.
 */

/**
 * @typedef {Object & Event} PhoenixEvent This type represents a custom Phoenix event.
 * @property {EventDetails} detail The event details
 */

/**
 * Handles the Phoenix back end event that requires triggering a notification.
 * @param {PhoenixEvent} event The event triggered from the back-end.
 * @returns {?Promise<Notification>} The notification that was triggered, undefined if no notification was triggered.
 */
export const pushBackEndNotification = (event) => {
  const mustCheckWindowFocus = event.detail.check_focus
  const browserWindowNotInFocus = document.hidden

  if (!mustCheckWindowFocus || browserWindowNotInFocus) {
    const title = "Privee - Text received"
    const url = `/chat/${event.detail.session_name}`

    const notification = new Notification(title, {
      body: event.detail.text,
      icon: "/favicon.ico",
    })

    // Open the chat when the notification is clicked.
    notification.addEventListener("click", () => window.open(url, "_blank"))

    return new Promise((resolve, _reject) => {
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") {
          resolve(notification)
        }
      })
    })
  } else {
    return Promise.resolve(undefined)
  }
}
