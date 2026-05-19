import { generateRegistrationKeys, exportPreKeyBundle } from "../utils/signal-protocol.mjs"
import {
  storeIdentityKeyPair,
  storeRegistrationId,
  storeSignedPreKey,
  storeOneTimePreKey,
  storePreKeyBundle,
} from "../utils/signal-store.mjs"

/** @type {import("../utils/signal-protocol.mjs").PreKeyBundle | null} */
let pendingPreKeyBundle = null

/**
 * Adds the hooks to the registration screen.
 * @param {any} Hooks The LiveView Hooks.
 */
export function addRegistrationHooks(Hooks) {
  Hooks.RegistrationScreen = {
    mounted() {
      // Disable submit until keys are generated to prevent race condition
      const submitBtn = this.el.querySelector("button[name=action]")
      if (submitBtn) submitBtn.disabled = true

      generateAndStoreKeys().then(() => {
        if (submitBtn) submitBtn.disabled = false
      })

      // When registration succeeds, POST the prekey bundle to the API endpoint
      this.handleEvent("handle_new_session_registration", async (/** @type {any} */ data) => {
        await registerPreKeyBundleViaAPI(data.session_id)
      })
    },
  }
}

/**
 * Generates Signal Protocol keys and stores them in IndexedDB.
 * The prekey bundle is held in memory until registration completes.
 */
const generateAndStoreKeys = async () => {
  try {
    const keys = await generateRegistrationKeys(10)

    // Store all private key material in IndexedDB
    await storeIdentityKeyPair(keys.identityKeyPair)
    await storeRegistrationId(keys.registrationId)
    await storeSignedPreKey(
      keys.signedPreKey.keyId,
      keys.signedPreKey.keyPair,
      keys.signedPreKey.signature,
    )

    for (const opk of keys.oneTimePreKeys) {
      await storeOneTimePreKey(opk.keyId, opk.keyPair)
    }

    // Export the public prekey bundle for uploading to server
    pendingPreKeyBundle = await exportPreKeyBundle(keys)
    // Persist the bundle so ChatScreen can re-upload it on mount
    await storePreKeyBundle(pendingPreKeyBundle)
    console.debug("Signal keys generated and stored")
  } catch (e) {
    console.error("Failed to generate Signal keys:", e)
  }
}

/**
 * Registers the prekey bundle with the server via a direct HTTP POST.
 * This is more reliable than injecting hidden form fields because it doesn't
 * depend on LiveView DOM patching or form submission timing.
 * @param {number} sessionId - The newly created session's ID
 */
const registerPreKeyBundleViaAPI = async (sessionId) => {
  if (!pendingPreKeyBundle || !sessionId) {
    console.warn("No prekey bundle available to register")
    return
  }

  const payload = {
    identity_key: pendingPreKeyBundle.identityKey,
    registration_id: pendingPreKeyBundle.registrationId,
    signed_prekey: {
      key_id: pendingPreKeyBundle.signedPreKey.keyId,
      public_key: pendingPreKeyBundle.signedPreKey.publicKey,
      signature: pendingPreKeyBundle.signedPreKey.signature,
    },
    one_time_prekeys: pendingPreKeyBundle.oneTimePreKeys.map((pk) => ({
      key_id: pk.keyId,
      public_key: pk.publicKey,
    })),
  }

  try {
    const resp = await fetch(`/api/prekeys/${sessionId}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      keepalive: true,
    })

    if (resp.ok) {
      console.debug("Prekey bundle registered via API for session:", sessionId)
    } else {
      console.error("Failed to register prekey bundle:", resp.status)
    }
  } catch (e) {
    console.error("Failed to register prekey bundle via API:", e)
  }
}

/**
 * Gets the pending prekey bundle for upload to the server.
 * @returns {import("../utils/signal-protocol.mjs").PreKeyBundle | null}
 */
export const getPendingPreKeyBundle = () => pendingPreKeyBundle
