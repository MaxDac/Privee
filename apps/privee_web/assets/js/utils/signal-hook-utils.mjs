/**
 * Glue between LiveView hooks and the Signal client.
 */

import { SignalClient } from "./signal-client.mjs"

const PUSH_TIMEOUT_MS = 15_000

/**
 * Wraps `hook.pushEvent` in a promise resolved with the server reply.
 * @param {{pushEvent: (event: string, payload: object, onReply: (reply: any) => void) => void}} hook
 * @param {number} [timeoutMs]
 * @returns {import("./signal-client.mjs").Push}
 */
export const replyPush =
  (hook, timeoutMs = PUSH_TIMEOUT_MS) =>
  (event, payload) =>
    new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`${event} timed out`)), timeoutMs)
      hook.pushEvent(event, payload, (reply) => {
        clearTimeout(timer)
        resolve(reply)
      })
    })

/**
 * Opens the Signal client of the session owning the page.
 * @param {any} hook LiveView hook instance.
 * @param {string | number} ownId
 * @returns {Promise<SignalClient>}
 */
export const openClientFor = (hook, ownId) => SignalClient.open({ ownId, push: replyPush(hook) })
