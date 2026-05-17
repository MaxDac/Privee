import { generateRegistrationKeys, exportPreKeyBundle } from "../utils/signal-protocol.mjs"
import {
  storeIdentityKeyPair,
  storeRegistrationId,
  storeSignedPreKey,
  storeOneTimePreKey,
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
      generateAndStoreKeys()
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
    console.debug("Signal keys generated and stored")
  } catch (e) {
    console.error("Failed to generate Signal keys:", e)
  }
}

/**
 * Gets the pending prekey bundle for upload to the server.
 * @returns {import("../utils/signal-protocol.mjs").PreKeyBundle | null}
 */
export const getPendingPreKeyBundle = () => pendingPreKeyBundle
