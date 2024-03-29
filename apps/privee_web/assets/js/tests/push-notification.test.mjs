import { describe, it, expect } from "vitest"
import { NotificationMock, getDom } from "./mock-utils.mjs"
import { askNotificationPermission, pushBackEndNotification } from "../utils/push-notifications.mjs"

describe("askNotificationPermission", () => {
  it("asks for permission, browser does not support notifications, reports the right result", () => {
    const dom = getDom()

    // @ts-ignore
    global.window = dom.window
    // @ts-ignore
    global.Notification = dom.window.Notification

    const expected = "This browser does not support notifications."
    return askNotificationPermission().catch((error) => expect(error).toBe(expected))
  })

  it("asks for permission, user accepts, reports the right result", async () => {
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
    expect(result).toBe(expected)
  })

  it("asks for permission, user denies, reports the right result", async () => {
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
    expect(result).toBe(expected)
  })
})

describe("pushBackEndNotification", () => {
  it("checking focus, does not trigger notification if the document is visible", async () => {
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

    expect(notification).toBeFalsy()
  })

  it("checking focus, does trigger notification if the document is not visible", async () => {
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

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(notification.body).toBe(notificationText)
    expect(notification.icon).toBe("/favicon.ico")
  })

  it("not checking focus, does trigger notification independent of the document visibility", async () => {
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

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(notification.body).toBe(notificationText)
    expect(notification.icon).toBe("/favicon.ico")
  })
})
