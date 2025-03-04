import { getPrivateKey } from "./message-encryption.mjs"
import { decryptMessage } from "./security.mjs"

/**
 * Determines whether the browser supports notifications, if not it logs it,
 * if it supports it asks for permission to the user and logs the result.
 * @returns {Promise<string>} The result of the permission request.
 */
export const askNotificationPermission = async () => {
  if ("Notification" in window) {
    await Notification.requestPermission()
    return `Permission: ${Notification.permission === "granted" ? "granted" : "denied"}`
  } else {
    return Promise.reject("This browser does not support notifications.")
  }
}

/**
 * @typedef {object} EventDetails Represents the details of the event sent from the back end. For more information read `events.ex` file.
 * @property {string} [text] The text of the message that triggered the notification.
 * @property {string} [session_name] The session name that sent the message.
 * @property {boolean} [check_focus] Whether to check if the window is in focus before triggering the notification.
 */

/**
 * @typedef {object & Event} PhoenixEvent This type represents a custom Phoenix event.
 * @property {EventDetails} detail The event details
 */

/**
 * Handles the Phoenix back end event that requires triggering a notification.
 * @param {PhoenixEvent} event The event triggered from the back-end.
 * @returns {Promise<?Notification>} The notification that was triggered, undefined if no notification was triggered.
 */
export const pushBackEndNotification = async (event) => {
  const mustCheckWindowFocus = event.detail.check_focus
  const browserWindowNotInFocus = document.hidden

  if (!mustCheckWindowFocus || browserWindowNotInFocus) {
    const title = "Privee - Text received"
    const url = `/chat/${event.detail.session_name}`
    const message = await getNotificationMessage(event)

    const notification = new Notification(title, {
      body: message,
      icon: "/favicon.ico",
    })

    // Open the chat when the notification is clicked.
    notification.addEventListener("click", () => window.open(url, "_blank"))

    const sendNotification = () =>
      new Promise((resolve, _reject) =>
        document.addEventListener("visibilitychange", () => {
          if (document.visibilityState === "visible") {
            resolve(notification)
          }
        }),
      )

    return await sendNotification()
  } else {
    return undefined
  }
}

/**
 * Handles the decryption of the notification message.
 * @param {PhoenixEvent} event The event triggered from the back-end.
 * @returns {Promise<string>} The decrypted message.
 */
const getNotificationMessage = async (event) => {
  const encryptedMessage = event.detail.text
  const receiverSessionName = event.detail.receiver_session_name

  let decryptedMessage = ""

  if (receiverSessionName != null && receiverSessionName != "") {
    // Getting the private key to decrypt the message in the user notification.
    const privateKey = await getPrivateKey(receiverSessionName)

    if (privateKey) {
      decryptedMessage = await decryptMessage(encryptedMessage, privateKey)
    }
  }

  return decryptedMessage
}
