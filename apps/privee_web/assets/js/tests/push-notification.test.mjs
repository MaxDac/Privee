import { describe, it, expect, vi, afterEach } from "vitest"
import { NotificationMock, getDom } from "./mock-utils.mjs"
import {
  askNotificationPermission,
  pushBackEndNotification,
  setNotificationCoordinator,
} from "../utils/push-notifications.mjs"

const addRequiredMockedMethod = (window) => ({
  ...window,
  open: (_url, _target, _features) => window,
})

// Coordinator that always allows notifications (single-tab behaviour)
const alwaysAllowCoordinator = {
  shouldShowNotification: () => Promise.resolve(true),
  destroy: () => {},
}

// Coordinator that always suppresses notifications
const alwaysSuppressCoordinator = {
  shouldShowNotification: () => Promise.resolve(false),
  destroy: () => {},
}

describe("askNotificationPermission", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
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
    vi.restoreAllMocks()
    setNotificationCoordinator(alwaysAllowCoordinator)
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
    setNotificationCoordinator(alwaysAllowCoordinator)
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

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: true,
        session_name: "session-abc",
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(notification.body).toBe("New message received")
    expect(notification.icon).toBe("/favicon.ico")
  })

  it("not checking focus, does trigger notification with generic message", async () => {
    setNotificationCoordinator(alwaysAllowCoordinator)
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

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        session_name: "session-abc",
      },
    })

    expect(notification).toBeTruthy()
    expect(notification.title).toBe("Privee - Text received")
    expect(notification.body).toBe("New message received")
    expect(notification.icon).toBe("/favicon.ico")
  })

  it("opens or focuses chat window with session-specific name", async () => {
    setNotificationCoordinator(alwaysAllowCoordinator)
    const dom = getDom()

    const focus = vi.fn()
    const open = vi.fn(() => ({ focus }))

    vi.stubGlobal("window", { ...dom.window, open })
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

    await pushBackEndNotification({
      detail: {
        check_focus: false,
        session_name: "session-xyz",
      },
    })

    expect(open).toHaveBeenCalledWith("/chat/session-xyz", "privee-chat-session-xyz")
    expect(focus).toHaveBeenCalled()
  })

  it("suppresses notification when coordinator rejects", async () => {
    setNotificationCoordinator(alwaysSuppressCoordinator)
    const dom = getDom()

    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
    })
    vi.stubGlobal("Notification", NotificationMock)

    const notification = await pushBackEndNotification({
      detail: {
        check_focus: false,
        session_name: "session-xyz",
      },
    })

    expect(notification).toBeUndefined()
  })
})
