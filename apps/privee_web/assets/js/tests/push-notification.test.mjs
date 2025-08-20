import { describe, it, expect, vi, afterEach } from "vitest"
import { NotificationMock, getDom } from "./mock-utils.mjs"
import { askNotificationPermission, pushBackEndNotification } from "../utils/push-notifications.mjs"
import { generateNewKeyPair } from "../utils/security.mjs"
import { encryptMessage } from "../utils/message-encryption.mjs"
import * as security from "../utils/security.mjs"

const addRequiredMockedMethod = (window) => ({
  ...window,
  open: (_url, _target, _features) => window,
})

describe("askNotificationPermission", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("asks for permission, browser does not support notifications, reports the right result", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("Notification", dom.window.Notification)

    const expected = "This browser does not support notifications."

    try {
      await askNotificationPermission()
      expect.fail("The function call should fail.")
    } catch (error) {
      expect(error).toBe(expected)
    }
  })

  it("asks for permission, user accepts, reports the right result", async () => {
    const dom = getDom()
    const window = addRequiredMockedMethod({
      ...dom.window,
      Notification: {
        requestPermission: () => Promise.resolve(),
        permission: "granted",
      },
    })

    vi.stubGlobal("window", window)
    vi.stubGlobal("Notification", window.Notification)

    const expected = "Permission: granted"
    const result = await askNotificationPermission()
    expect(result).toBe(expected)
  })

  it("asks for permission, user denies, reports the right result", async () => {
    const dom = getDom()
    const window = addRequiredMockedMethod({
      ...dom.window,
      Notification: {
        requestPermission: () => Promise.resolve(),
        permission: "denied",
      },
    })

    vi.stubGlobal("window", window)
    vi.stubGlobal("Notification", window.Notification)

    const expected = "Permission: denied"
    const result = await askNotificationPermission()
    expect(result).toBe(expected)
  })
})

describe("pushBackEndNotification", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("checking focus, does not trigger notification if the document is visible", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
    })

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: true,
      },
    })

    expect(notification).toBeFalsy()
  })

  it("checking focus, does trigger notification if the document is not visible", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: true,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    })
    vi.stubGlobal("Notification", NotificationMock)

    // Mocking getting the private key
    const { privateKey, publicKey } = await generateNewKeyPair()
    const receiverSessionName = "sesssion-name"

    const getPrivateKeyMock = vi.spyOn(security, "getPrivateKey").mockImplementation((sn) => {
      if (sn === receiverSessionName) {
        return Promise.resolve(privateKey)
      }

      return Promise.reject(`Not the right session name. Session name passed '${sn}'.`)
    })

    const notificationText = "notification text"

    const encryptedNotificationText = await encryptMessage(notificationText, publicKey)

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: true,
        receiver_session_name: receiverSessionName,
        text: encryptedNotificationText,
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(getPrivateKeyMock).toHaveBeenCalledOnce()
    expect(notification.body).toBe(notificationText)
    expect(notification.icon).toBe("/favicon.ico")
  })

  it("not checking focus, does trigger notification independent of the document visibility", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    })
    vi.stubGlobal("Notification", NotificationMock)

    // Mocking getting the private key
    const { privateKey, publicKey } = await generateNewKeyPair()
    const receiverSessionName = "sesssion-name"

    const getPrivateKeyMock = vi.spyOn(security, "getPrivateKey").mockImplementation((sn) => {
      if (sn === receiverSessionName) {
        return Promise.resolve(privateKey)
      }

      return Promise.reject(`Not the right session name. Session name passed '${sn}'.`)
    })

    const notificationText = "notification text"

    const encryptedNotificationText = await encryptMessage(notificationText, publicKey)

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        receiver_session_name: receiverSessionName,
        text: encryptedNotificationText,
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(getPrivateKeyMock).toHaveBeenCalledOnce()
    expect(notification.body).toBe(notificationText)
    expect(notification.icon).toBe("/favicon.ico")
  })

  it("The browser did not store the private key, text is empty", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    })
    vi.stubGlobal("Notification", NotificationMock)

    // Mocking getting the private key
    const { publicKey } = await generateNewKeyPair()
    const receiverSessionName = "sesssion-name"

    const getPrivateKeyMock = vi
      .spyOn(security, "getPrivateKey")
      .mockImplementation(() => Promise.resolve(undefined))

    const notificationText = "notification text"

    const encryptedNotificationText = await encryptMessage(notificationText, publicKey)

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        receiver_session_name: receiverSessionName,
        text: encryptedNotificationText,
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.text).toBeFalsy()
    expect(getPrivateKeyMock).toHaveBeenCalledOnce()
  })

  it("The browser does not receive the receiver session id, text is empty", async () => {
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") {
          callback()
        }
      },
    })
    vi.stubGlobal("Notification", NotificationMock)

    // Mocking getting the private key
    const { publicKey } = await generateNewKeyPair()

    const getPrivateKeyMock = vi
      .spyOn(security, "getPrivateKey")
      .mockImplementation(() => Promise.resolve(undefined))

    const notificationText = "notification text"

    const encryptedNotificationText = await encryptMessage(notificationText, publicKey)

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        text: encryptedNotificationText,
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(getPrivateKeyMock).toHaveBeenCalledTimes(0)
    expect(notification.body).toBeFalsy()
    expect(notification.icon).toBe("/favicon.ico")
  })
})
