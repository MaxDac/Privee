/**
  * Determines whether the browser supports notifications, if not it logs it,
  * if it supports it asks for permission to the user and logs the result.
  */
export const askNotificationPermission = () => {
  const handlePermission = (_) => {
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
    * Shows a notification with the given body and an optional title.
    * @param {string} [body] - The body of the notification.
    * @param {string} [title] - The title of the notification.
    * @param {string} [url] - The url to open when the notification is clicked.
    * @returns {Promise<?Notification>} - The notification.
    */
export const pushNotification = (body, title, url) => {
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
}

/**
  * @typedef {Object & Event} PhoenixEvent This type represents a custom Phoenix event.
  * @property {any} detail The event details
  */

/**
 * Handles the Phoenix back end event that requires triggering a notification.
 * @param {PhoenixEvent} event The event triggered from the back-end.
 */
export const phoenixPushEventHandler = (event) => {
  console.debug("Phoenix event received: ", event)
  pushNotification(event.detail.text, "Privee - Text received", `/chat/${event.detail.session_name}`)
    .catch(e => console.error("Error showing notification: ", e))
}
