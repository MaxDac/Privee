import { describe, it, expect, vi, afterEach } from "vitest"
import { NotificationMock, getDom } from "./mock-utils.mjs"
import { installCatalog } from "./gettext-fixture.mjs"
import {
  askNotificationPermission,
  askNotificationPermissionOnGesture,
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

describe("notification language changes", () => {
  afterEach(() => vi.unstubAllGlobals())

  it("uses localized generic presentation rather than private message content", async () => {
    setNotificationCoordinator(alwaysAllowCoordinator)
    const dom = getDom()
    installCatalog(dom.window.document, "pt-PT")
    vi.stubGlobal("window", addRequiredMockedMethod(dom.window))
    vi.stubGlobal("document", {
      ...dom.window.document,
      hidden: false,
      visibilityState: "visible",
      addEventListener: (type, callback) => {
        if (type === "visibilitychange") callback()
      },
    })
    vi.stubGlobal("Notification", NotificationMock)
    const notification = await pushBackEndNotification({
      detail: { check_focus: false, session_name: "unchanged-name", text: "private message" },
    })
    expect(notification.title).toBe("Privee - Mensagem recebida")
    expect(notification.body).toBe("Nova mensagem recebida")
  })
})

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

describe("askNotificationPermissionOnGesture", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  const stub = (permission) => {
    const dom = getDom()
    const requestPermission = vi.fn(() => {
      Notification.permission = "granted"
      return Promise.resolve("granted")
    })
    const notification = { permission, requestPermission }
    vi.stubGlobal("window", { ...dom.window, Notification: notification })
    vi.stubGlobal("Notification", notification)
    return { doc: dom.window.document, requestPermission }
  }

  it("waits for a click or tap of a signed-in session before asking", async () => {
    const { doc, requestPermission } = stub("default")
    const result = askNotificationPermissionOnGesture(doc)
    await Promise.resolve()
    expect(requestPermission).not.toHaveBeenCalled()

    doc.body.dispatchEvent(new doc.defaultView.MouseEvent("click", { bubbles: true }))
    expect(requestPermission).not.toHaveBeenCalled()

    const menu = doc.createElement("button")
    menu.id = "copy-session-code-btn"
    doc.body.append(menu)
    doc.body.dispatchEvent(new doc.defaultView.KeyboardEvent("keydown", { bubbles: true }))
    expect(requestPermission).not.toHaveBeenCalled()

    doc.body.dispatchEvent(new doc.defaultView.MouseEvent("click", { bubbles: true }))
    expect(await result).toBe("Permission: granted")
    doc.body.dispatchEvent(new doc.defaultView.MouseEvent("click", { bubbles: true }))
    expect(requestPermission).toHaveBeenCalledTimes(1)
  })

  it("does not ask again once the user decided", async () => {
    const { doc, requestPermission } = stub("denied")
    expect(await askNotificationPermissionOnGesture(doc)).toBe("Permission: denied")
    doc.body.dispatchEvent(new doc.defaultView.MouseEvent("click", { bubbles: true }))
    expect(requestPermission).not.toHaveBeenCalled()
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
