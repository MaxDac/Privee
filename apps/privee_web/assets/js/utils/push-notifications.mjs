/**
  * Determines whether the browser supports notifications, if not it logs it,
  * if it supports it asks for permission to the user and logs the result.
  */
export const askNotificationPermission = () => {
  const handlePermission = () => {
    console.debug("Permission: ", Notification.permission === "granted" ? "granted" : "denied")
  }
  
  if ("Notification" in window) {
    Notification.requestPermission()
      .then(handlePermission)
  }
  else {
    console.debug("This browser does not support notifications.")
  }
}

/**
  * Determines whether the chat window is currently on focus.
  */
const isWindowCurrentlyHidden = () => document.hidden
  
/**
  * Shows a notification with the given body and an optional title.
  * @param {string} [body] - The body of the notification.
  * @param {string} [title] - The title of the notification.
  * @param {string} [url] - The url to open when the notification is clicked.
  * @param {boolean} [checkFocus] - Determines whether to check if the window is in focus 
  * before sending the notification.
  * @returns {Promise<?Notification>} - The notification.
  */
export const pushNotification = (body, title, url, checkFocus) => {
  if (!checkFocus || isWindowCurrentlyHidden()) {
    const imageUrl = "/favicon.ico"
    const notificationTitle = title || " - Privee new notification"

    const notification = new Notification(notificationTitle, {
      body: body,
      icon: imageUrl
    })

    // Open the chat when the notification is clicked.
    notification.addEventListener("click", (_) => {
      if (url) {
        window.open(url, "_blank")
      }
    })
      
    return new Promise((resolve, _reject) => {
      document.addEventListener("visibilitychange", (_) => {
        if (document.visibilityState === "visible") {
          resolve(notification)
        }
      })
    })
  } else {
    return Promise.resolve(undefined)
  }
}

/**
  * @typedef {Object} EventDetails Represents the details of the event sent from the back end. For more information
  * consult `events.ex` file.
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
 */
export const phoenixPushEventHandler = (event) => {
  pushNotification(event.detail.text, "Privee - Text received", `/chat/${event.detail.session_name}`, event.detail.check_focus)
    .catch(e => console.error("Error showing notification: ", e))
}
