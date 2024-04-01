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
import { addChatHooks } from "./hooks/chat-hooks.mjs"
import { addRegistrationHooks } from "./hooks/registration-hooks.mjs"
import { exportDebugFunctions } from "./utils/debug.mjs"
import { addBackEndEventHandlers } from "./hooks/event-handlers.mjs"

// Setting up LiveView hooks
const Hooks = {}
addRegistrationHooks(Hooks)
addChatHooks(Hooks)

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })

// connect if there are any LiveViews on the page
liveSocket.connect()

// Adds all the event handlers
addBackEndEventHandlers()

// Only activate this in debug mode
exportDebugFunctions()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// @ts-ignore
window.liveSocket = liveSocket
