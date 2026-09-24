import { createNotificationCoordinator } from "./notification-coordinator.mjs"

/** @type {import("./notification-coordinator.mjs").NotificationCoordinator} */
let coordinator = createNotificationCoordinator()

/**
 * Replaces the active notification coordinator (useful for testing).
 * @param {import("./notification-coordinator.mjs").NotificationCoordinator} c
 */
export const setNotificationCoordinator = (c) => {
  coordinator = c
}

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
 * @property {string} [body] The body text associated with the event.
 * @property {string} [session_name] The session name that sent the message.
 * @property {string} [message_id] The id of the received message, used for cross-tab dedup.
 * @property {number} [to] The receiver session id.
 * @property {boolean} [check_focus] Whether to check if the window is in focus before triggering the notification.
 */

/**
 * @typedef {object} PhoenixEvent This type represents a custom Phoenix event.
 * @property {EventDetails} detail The event details
 */

/**
 * Handles the Phoenix back end event that requires triggering a notification.
 * @param {PhoenixEvent} event The event triggered from the back-end.
 * @returns {Promise<Notification|undefined>} The notification that was triggered, undefined if no notification was triggered.
 */
export const pushBackEndNotification = async (event) => {
  const mustCheckWindowFocus = event.detail.check_focus
  const browserWindowNotInFocus = document.hidden

  if (!mustCheckWindowFocus || browserWindowNotInFocus) {
    const sessionName = /** @type {string} */ (event.detail.session_name)

    // Cross-tab deduplication: only one tab should show the notification
    const { message_id: messageId, to } = event.detail
    const dedupKey = messageId ? `${to}:${messageId}` : sessionName
    const allowed = await coordinator.shouldShowNotification(sessionName, dedupKey)
    if (!allowed) return undefined

    const title = "Privee - Text received"
    const url = `/chat/${sessionName}`
    const message = await getNotificationMessage(event)

    const notification = new Notification(title, {
      body: message,
      icon: "/favicon.ico",
    })

    const windowName = getChatWindowName(sessionName)

    // Open or focus the chat when the notification is clicked.
    notification.addEventListener("click", () => {
      const win = window.open(url, windowName)
      if (win?.focus) win.focus()
      notification.close?.()
    })

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
 * With Signal Protocol, we cannot decrypt outside the ratchet session context,
 * so notifications show a generic message.
 * @param {PhoenixEvent} _event The event triggered from the back-end.
 * @returns {Promise<string>} The notification message.
 */
const getNotificationMessage = (_event) => {
  return Promise.resolve("New message received")
}

/**
 * @param {string} sessionName
 * @returns {string}
 */
const getChatWindowName = (sessionName) => `privee-chat-${sessionName}`
