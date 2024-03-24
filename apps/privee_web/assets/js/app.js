// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
// @ts-ignore
import { Socket } from "phoenix"
// @ts-ignore
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Importing Flowbite
import "flowbite/dist/flowbite.phoenix.js"

// Importing utility functions
import { addToggleDarkModeHandling, setStartupTheme } from "./utils/dark-mode-switcher.mjs"
import { askNotificationPermission, pushBackEndNotification } from "./utils/push-notifications.mjs"
import { addSessionNameCopyListener, copyToClipboardBackEndEventHandler } from "./utils/clipboard.mjs"
import { addChatHooks } from "./hooks/chat-hooks.mjs"

// Setting up LiveView hooks
const Hooks = {}
addChatHooks(Hooks)

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => {
  topbar.hide()

  // Adding this because for some reason it gets reset at page load.
  setStartupTheme()
})

document.addEventListener("DOMContentLoaded", addToggleDarkModeHandling)

// Asking for notification permission to the browser
askNotificationPermission()
  .then(console.debug)
  .catch(console.error)

// Setting the LiveView events
window.addEventListener("phx:trigger_notification", pushBackEndNotification)
window.addEventListener("phx:copy_to_clipboard", copyToClipboardBackEndEventHandler)

addSessionNameCopyListener()

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// @ts-ignore
window.liveSocket = liveSocket

