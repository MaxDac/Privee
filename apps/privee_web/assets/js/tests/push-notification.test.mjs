import test from "ava"
import { NotificationMock, getDom } from "./mock-utils.mjs"
import { askNotificationPermission, pushBackEndNotification } from "../utils/push-notifications.mjs"

test.serial(
  "askNotificationPermission asks for permission, browser does not support notifications, reports the right result",
  (t) => {
    const dom = getDom()

    // @ts-ignore
    global.window = dom.window
    // @ts-ignore
    global.Notification = dom.window.Notification

    const expected = "This browser does not support notifications."
    return askNotificationPermission().catch((error) => t.is(error, expected))
  },
)

test.serial("askNotificationPermission asks for permission, user accepts, reports the right result", async (t) => {
  const dom = getDom()
  const window = {
    ...dom.window,
    Notification: {
      requestPermission: () => Promise.resolve(),
      permission: "granted",
    },
  }

  // @ts-ignore
  global.window = window
  // @ts-ignore
  global.Notification = window.Notification

  const expected = "Permission: granted"
  const result = await askNotificationPermission()
  t.is(result, expected)
})

test.serial("askNotificationPermission asks for permission, user denies, reports the right result", async (t) => {
  const dom = getDom()
  const window = {
    ...dom.window,
    Notification: {
      requestPermission: () => Promise.resolve(),
      permission: "denied",
    },
  }

  // @ts-ignore
  global.window = window
  // @ts-ignore
  global.Notification = window.Notification

  const expected = "Permission: denied"
  const result = await askNotificationPermission()
  t.is(result, expected)
})

test.serial(
  "pushBackEndNotification checking focus, does not trigger notification if the document is visible",
  async (t) => {
    const dom = getDom()

    // @ts-ignore
    global.window = {
      ...window,
      open: (_url, _target, _features) => window,
    }

    global.document = {
      ...dom.window.document,
      hidden: false,
    }

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: true,
      },
    })

    t.falsy(notification)
  },
)

test.serial(
  "pushBackEndNotification checking focus, does trigger notification if the document is not visible",
  async (t) => {
    const dom = getDom()

    // @ts-ignore
    global.window = window

    global.document = {
      ...dom.window.document,
      hidden: true,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    }

    // @ts-ignore
    global.Notification = NotificationMock

    const notificationText = "Hello, world!"

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: true,
        text: notificationText,
      },
    })

    t.truthy(notification)
    t.is(notification.title, "Privee - Text received")
    t.is(notification.body, notificationText)
    t.is(notification.icon, "/favicon.ico")
  },
)

test.serial(
  "pushBackEndNotification not checking focus, does trigger notification independent of the document visibility",
  async (t) => {
    const dom = getDom()

    // @ts-ignore
    global.window = window

    global.document = {
      ...dom.window.document,
      hidden: false,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    }

    // @ts-ignore
    global.Notification = NotificationMock

    const notificationText = "Hello, world!"

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        text: notificationText,
      },
    })

    t.truthy(notification)
    t.is(notification.title, "Privee - Text received")
    t.is(notification.body, notificationText)
    t.is(notification.icon, "/favicon.ico")
  },
)
