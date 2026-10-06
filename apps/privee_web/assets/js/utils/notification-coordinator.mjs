/**
 * Cross-tab notification coordinator using BroadcastChannel API.
 *
 * When multiple browser tabs are open for the same user (e.g. the session
 * selector and a chat tab), each tab's LiveView independently pushes
 * `trigger_notification` events. Without coordination every tab would fire
 * its own browser Notification, producing duplicates.
 *
 * Protocol: deterministic election within a coordination window.
 *   1. Tab receives a notification event and broadcasts a "claim" with its
 *      priority and unique tabId.
 *   2. After CLAIM_TIMEOUT_MS the tab computes the winner from all claims
 *      it collected (highest priority, then lowest tabId as tie-breaker).
 *   3. The winner shows the notification and broadcasts "shown".
 *   4. Losers wait for the winner's "shown" confirmation. If it doesn't
 *      arrive within FAILOVER_TIMEOUT_MS, losers re-elect among remaining
 *      candidates (excluding the crashed winner) deterministically.
 *
 * Priority order:
 *   3 – focused chat tab for the sender's session
 *   2 – unfocused chat tab for the sender's session
 *   1 – any other focused tab
 *   0 – unfocused non-chat tab
 *
 * If the browser does not support BroadcastChannel the coordinator is a
 * no-op pass-through so notifications still work in older environments.
 */

const CHANNEL_NAME = "privee-notifications"
const DEDUP_WINDOW_MS = 2000
const CLAIM_TIMEOUT_MS = 150
const FAILOVER_TIMEOUT_MS = 500

/**
 * @typedef {object} NotificationCoordinator
 * @property {(sessionName: string) => Promise<boolean>} shouldShowNotification
 * @property {() => void} destroy
 */

/**
 * Creates a cross-tab notification coordinator.
 * @returns {NotificationCoordinator}
 */
export const createNotificationCoordinator = () => {
  if (typeof BroadcastChannel === "undefined") {
    return { shouldShowNotification: () => Promise.resolve(true), destroy: () => {} }
  }

  const channel = new BroadcastChannel(CHANNEL_NAME)
  const tabId = generateTabId()

  /**
   * Active elections, keyed by sessionName.
   * @type {Map<string, {waiters: Array<(v: boolean) => void>, claimTimeout: ReturnType<typeof setTimeout>, failoverTimeout: ReturnType<typeof setTimeout> | null, claims: Array<{priority: number, claimantTabId: string}>, myClaim: {priority: number, claimantTabId: string}}>}
   */
  const elections = new Map()

  /**
   * Recently shown notifications for dedup, keyed by sessionName.
   * @type {Map<string, number>}
   */
  const recentlyShown = new Map()

  /**
   * Resolve all waiters and clean up an election entry.
   * @param {string} sessionName
   * @param {boolean} value
   */
  const resolveElection = (sessionName, value) => {
    const election = elections.get(sessionName)
    if (!election) return
    clearTimeout(election.claimTimeout)
    if (election.failoverTimeout) clearTimeout(election.failoverTimeout)
    for (const waiter of election.waiters) waiter(value)
    elections.delete(sessionName)
  }

  channel.onmessage = (event) => {
    const { type, sessionName, priority, claimantTabId } = event.data

    if (type === "claim" && claimantTabId !== tabId) {
      const election = elections.get(sessionName)
      if (election) {
        election.claims.push({ priority, claimantTabId })
      }
    }

    if (type === "shown" && claimantTabId !== tabId) {
      recentlyShown.set(sessionName, Date.now())
      resolveElection(sessionName, false)
    }
  }

  /**
   * Determines whether this tab should show the notification for a given
   * sender session.
   * @param {string} sessionName The sender's session name.
   * @returns {Promise<boolean>}
   */
  const shouldShowNotification = (sessionName) => {
    if (!sessionName) return Promise.resolve(false)

    // Prune expired dedup entries
    const now = Date.now()
    for (const [key, ts] of recentlyShown) {
      if (now - ts >= DEDUP_WINDOW_MS) recentlyShown.delete(key)
    }

    const lastShown = recentlyShown.get(sessionName)
    if (lastShown && Date.now() - lastShown < DEDUP_WINDOW_MS) {
      return Promise.resolve(false)
    }

    // Coalesce: if an election for this sessionName is already in progress,
    // join it but always resolve false — only the initiating call should act.
    const existing = elections.get(sessionName)
    if (existing) {
      return new Promise((resolve) => existing.waiters.push(() => resolve(false)))
    }

    const myPriority = getTabPriority(sessionName)
    const myClaim = { priority: myPriority, claimantTabId: tabId }

    return new Promise((resolve) => {
      const claimTimeout = setTimeout(() => {
        const election = elections.get(sessionName)
        if (!election) return

        const allClaims = [myClaim, ...election.claims]
        const winner = electWinner(allClaims)

        if (winner.claimantTabId === tabId) {
          // We won — show notification and announce
          recentlyShown.set(sessionName, Date.now())
          channel.postMessage({ type: "shown", sessionName, claimantTabId: tabId })
          resolveElection(sessionName, true)
        } else {
          // We lost — wait for winner's "shown", with coordinated failover
          election.failoverTimeout = setTimeout(() => {
            // Winner didn't confirm — re-elect among remaining candidates
            const remaining = allClaims.filter((c) => c.claimantTabId !== winner.claimantTabId)
            if (remaining.length === 0) {
              resolveElection(sessionName, false)
              return
            }

            const nextWinner = electWinner(remaining)
            if (nextWinner.claimantTabId === tabId) {
              recentlyShown.set(sessionName, Date.now())
              channel.postMessage({ type: "shown", sessionName, claimantTabId: tabId })
              resolveElection(sessionName, true)
            } else {
              // Not our turn in failover either — give up
              resolveElection(sessionName, false)
            }
          }, FAILOVER_TIMEOUT_MS)
        }
      }, CLAIM_TIMEOUT_MS)

      elections.set(sessionName, {
        waiters: [resolve],
        claimTimeout,
        failoverTimeout: null,
        claims: [],
        myClaim,
      })

      channel.postMessage({
        type: "claim",
        sessionName,
        priority: myPriority,
        claimantTabId: tabId,
      })
    })
  }

  const destroy = () => {
    for (const election of elections.values()) {
      clearTimeout(election.claimTimeout)
      if (election.failoverTimeout) clearTimeout(election.failoverTimeout)
      for (const waiter of election.waiters) waiter(false)
    }
    elections.clear()
    channel.close()
  }

  return { shouldShowNotification, destroy }
}

// -- Internals (exported for testing) ----------------------------------------

/**
 * Elects a winner from a list of claims. Highest priority wins; ties broken
 * by lowest tabId (lexicographic).
 * @param {Array<{priority: number, claimantTabId: string}>} claims
 * @returns {{priority: number, claimantTabId: string}}
 */
export const electWinner = (claims) => {
  return claims.reduce((best, claim) => {
    if (claim.priority > best.priority) return claim
    if (claim.priority === best.priority && claim.claimantTabId < best.claimantTabId) return claim
    return best
  })
}

/**
 * Priority for the current tab relative to a notification for `sessionName`.
 * @param {string} sessionName
 * @returns {number}
 */
export const getTabPriority = (sessionName) => {
  const isChatTab = window.name === `privee-chat-${sessionName}`
  const isFocused = document.hasFocus()

  if (isChatTab && isFocused) return 3
  if (isChatTab) return 2
  if (isFocused) return 1
  return 0
}

/**
 * Generates a unique tab identifier.
 * @returns {string}
 */
const generateTabId = () => {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID()
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`
}
