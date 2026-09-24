import "fake-indexeddb/auto"
import { IDBFactory } from "fake-indexeddb"
import { describe, it, expect, beforeEach, vi } from "vitest"
import {
  SignalClient,
  IdentityChangedError,
  DeviceNotReadyError,
  NoPeerKeysError,
  OPK_TARGET,
} from "../utils/signal-client.mjs"
import { createMemoryLocks, UnsupportedBrowserError } from "../utils/signal-locks.mjs"
import { Stores, dbNameFor } from "../utils/signal-db.mjs"
import { FakeServer } from "./signal-fake-server.mjs"

const ALICE = 1
const BOB = 2

/**
 * @param {FakeServer} server
 * @param {number} ownId
 * @param {number} peerId
 * @param {{factory?: IDBFactory, locks?: any}} [options]
 */
const device = async (server, ownId, peerId, options = {}) => {
  const factory = options.factory ?? new IDBFactory()
  const client = await SignalClient.open({
    ownId,
    push: server.connect(ownId, peerId),
    locks: options.locks ?? createMemoryLocks(),
    factory,
  })
  return { client, factory }
}

/**
 * Decrypts every message of `from` not yet in the history of `client`.
 * @param {FakeServer} server
 * @param {SignalClient} client
 * @param {number} ownId
 * @param {number} from
 */
const receiveAll = async (server, client, ownId, from) => {
  const out = []
  for (const message of server.inbox(ownId, from)) {
    out.push(await client.decryptMessage(from, message))
  }
  return out
}

describe("SignalClient", () => {
  /** @type {FakeServer} */
  let server

  beforeEach(() => {
    server = new FakeServer()
    vi.spyOn(console, "warn").mockImplementation(() => {})
  })

  describe("key management", () => {
    it("generates and publishes a bundle on first use", async () => {
      const { client } = await device(server, ALICE, BOB)
      expect(await client.ensureKeys()).toBe("ready")

      const bundle = server.bundles.get(ALICE)
      expect(bundle.identity_key).toBe(await client.identityKey())
      expect(bundle.one_time_prekeys).toHaveLength(OPK_TARGET)
      expect(bundle.signed_prekey.key_id).toBe(1)
    })

    it("is idempotent and does not republish keys", async () => {
      const { client } = await device(server, ALICE, BOB)
      await client.ensureKeys()
      const before = structuredClone(server.bundles.get(ALICE))
      await client.ensureKeys()
      expect(server.bundles.get(ALICE)).toEqual(before)
    })

    it("replenishes one-time prekeys with fresh, increasing ids", async () => {
      const { client } = await device(server, ALICE, BOB)
      await client.ensureKeys()
      const bundle = server.bundles.get(ALICE)
      bundle.one_time_prekeys.splice(0, OPK_TARGET - 5)

      await client.replenish()
      const ids = bundle.one_time_prekeys.map((/** @type {any} */ k) => k.key_id)
      expect(ids).toHaveLength(OPK_TARGET)
      expect(new Set(ids).size).toBe(ids.length)
      expect(Math.min(...ids.slice(5))).toBeGreaterThan(OPK_TARGET)
    })

    it("does not produce duplicate ids when replenishing concurrently", async () => {
      const locks = createMemoryLocks()
      const factory = new IDBFactory()
      const { client: tab1 } = await device(server, ALICE, BOB, { factory, locks })
      const { client: tab2 } = await device(server, ALICE, BOB, { factory, locks })
      await tab1.ensureKeys()
      server.bundles.get(ALICE).one_time_prekeys.splice(0, OPK_TARGET)

      await Promise.all([tab1.replenish(), tab2.replenish()])
      const ids = server.bundles.get(ALICE).one_time_prekeys.map((/** @type {any} */ k) => k.key_id)
      expect(ids).toHaveLength(OPK_TARGET)
      expect(new Set(ids).size).toBe(ids.length)
    })

    it("rotates the signed prekey after a week and keeps the old one", async () => {
      let now = Date.now()
      const factory = new IDBFactory()
      const client = await SignalClient.open({
        ownId: ALICE,
        push: server.connect(ALICE, BOB),
        locks: createMemoryLocks(),
        factory,
        now: () => now,
      })
      await client.ensureKeys()
      now += 8 * 24 * 3600 * 1000
      await client.ensureKeys()

      expect(server.bundles.get(ALICE).signed_prekey.key_id).toBe(2)
      const records = await client.operation().getAll(Stores.signedPrekeys)
      expect(records.map((r) => r.keyId).sort()).toEqual([1, 2])
    })

    it("keeps a retired signed prekey for PreKey messages sent before rotation", async () => {
      const start = Date.now()
      let now = start
      const alice = await SignalClient.open({
        ownId: ALICE,
        push: server.connect(ALICE, BOB),
        locks: createMemoryLocks(),
        factory: new IDBFactory(),
        now: () => now,
      })
      const bob = (await device(server, BOB, ALICE)).client
      await alice.ensureKeys()
      await bob.ensureKeys()

      // Alice is away for 9 days; Bob writes using her still-published SPK 1.
      now += 9 * 24 * 3600 * 1000
      await bob.send(ALICE, "while you were away")
      expect(await alice.ensureKeys()).toBe("ready")
      expect(server.bundles.get(ALICE).signed_prekey.key_id).toBe(2)

      const [message] = server.inbox(ALICE, BOB)
      expect(await alice.decryptMessage(BOB, message)).toBe("while you were away")

      // Pruned only once the retention has elapsed since its retirement.
      now += 9 * 24 * 3600 * 1000
      await alice.ensureKeys()
      const records = await alice.operation().getAll(Stores.signedPrekeys)
      expect(records.map((r) => r.keyId)).not.toContain(1)
    })

    it("requires a reset on a new device when the server has a bundle", async () => {
      const { client: first } = await device(server, ALICE, BOB)
      await first.ensureKeys()

      const { client: second } = await device(server, ALICE, BOB)
      expect(await second.ensureKeys()).toBe("needs_reset")
      await expect(second.encryptMessage(BOB, "hi", "e1")).rejects.toThrow(DeviceNotReadyError)

      expect(await second.resetIdentity()).toBe("ready")
      expect(await first.ensureKeys()).toBe("superseded")
      await expect(first.encryptMessage(BOB, "hi", "e1")).rejects.toThrow(DeviceNotReadyError)
    })

    it("republishes existing keys when the server lost the bundle", async () => {
      const { client } = await device(server, ALICE, BOB)
      await client.ensureKeys()
      const identity = await client.identityKey()
      server.bundles.delete(ALICE)

      expect(await client.ensureKeys()).toBe("ready")
      expect(server.bundles.get(ALICE).identity_key).toBe(identity)
    })

    it("fails closed without Web Locks", async () => {
      await expect(
        SignalClient.open({
          ownId: ALICE,
          push: server.connect(ALICE, BOB),
          factory: new IDBFactory(),
        }),
      ).rejects.toThrow(UnsupportedBrowserError)
    })
  })

  describe("messaging", () => {
    /** @type {SignalClient} */
    let alice
    /** @type {SignalClient} */
    let bob

    beforeEach(async () => {
      alice = (await device(server, ALICE, BOB)).client
      bob = (await device(server, BOB, ALICE)).client
      await alice.ensureKeys()
      await bob.ensureKeys()
    })

    it("delivers a first message, a reply and follow-ups", async () => {
      const sent = await alice.send(BOB, "hello bob")
      expect(sent?.direction).toBe("out")
      expect(sent?.plaintext).toBe("hello bob")
      expect(server.messages[0].type).toBe(3)

      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["hello bob"])

      await bob.send(ALICE, "hi alice")
      expect(await receiveAll(server, alice, ALICE, BOB)).toEqual(["hi alice"])

      await alice.send(BOB, "second")
      expect(server.messages[2].type).toBe(1)
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["hello bob", "second"])
    })

    it("does not consume a one-time prekey on every message", async () => {
      await alice.send(BOB, "one")
      await alice.send(BOB, "two")
      expect(server.bundles.get(BOB).one_time_prekeys).toHaveLength(OPK_TARGET - 1)
    })

    it("works when the peer has no one-time prekeys left", async () => {
      server.bundles.get(BOB).one_time_prekeys = []
      await alice.send(BOB, "no opk")
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["no opk"])
    })

    it("fails with NoPeerKeysError when the peer never published", async () => {
      server.bundles.delete(BOB)
      await expect(alice.send(BOB, "hi")).rejects.toThrow(NoPeerKeysError)
    })

    it("decrypts out-of-order messages", async () => {
      await alice.send(BOB, "a")
      await receiveAll(server, bob, BOB, ALICE)
      await bob.send(ALICE, "ack")
      await receiveAll(server, alice, ALICE, BOB)
      await alice.send(BOB, "b")
      await alice.send(BOB, "c")

      const [, second, third] = server.inbox(BOB, ALICE)
      expect(await bob.decryptMessage(ALICE, third)).toBe("c")
      expect(await bob.decryptMessage(ALICE, second)).toBe("b")
    })

    it("returns the cached plaintext for duplicate deliveries", async () => {
      await alice.send(BOB, "once")
      const [message] = server.inbox(BOB, ALICE)
      expect(await bob.decryptMessage(ALICE, message)).toBe("once")
      expect(await bob.decryptMessage(ALICE, message)).toBe("once")
    })

    it("handles glare (both sides initiate at once)", async () => {
      await Promise.all([alice.send(BOB, "from alice"), bob.send(ALICE, "from bob")])
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["from alice"])
      expect(await receiveAll(server, alice, ALICE, BOB)).toEqual(["from bob"])

      await alice.send(BOB, "after glare")
      await bob.send(ALICE, "after glare too")
      expect((await receiveAll(server, bob, BOB, ALICE)).at(-1)).toBe("after glare")
      expect((await receiveAll(server, alice, ALICE, BOB)).at(-1)).toBe("after glare too")
    })

    it("decrypts a PreKey message arriving after a Whisper message", async () => {
      await alice.send(BOB, "first")
      await alice.send(BOB, "second")
      const [first, second] = server.inbox(BOB, ALICE)
      expect(first.type).toBe(3)
      expect(second.type).toBe(3)
      expect(await bob.decryptMessage(ALICE, second)).toBe("second")
      expect(await bob.decryptMessage(ALICE, first)).toBe("first")
    })

    it("stores undecryptable messages as failed without throwing", async () => {
      await alice.send(BOB, "hi")
      const [message] = server.inbox(BOB, ALICE)
      const corrupted = { ...message, body: btoa("garbage") }
      expect(await bob.decryptMessage(ALICE, corrupted)).toBeNull()
      expect((await bob.historyEntry(message.id))?.plaintext).toBeNull()
    })

    it("keeps local history across reloads", async () => {
      await alice.send(BOB, "persisted")
      await receiveAll(server, bob, BOB, ALICE)
      const history = await alice.history(BOB)
      expect(history.map((h) => [h.direction, h.plaintext])).toEqual([["out", "persisted"]])
      expect((await bob.history(ALICE)).map((h) => h.plaintext)).toEqual(["persisted"])
    })

    it("acknowledges idempotently (reply and stream entry race)", async () => {
      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "race", epoch)
      const ack = { id: "m-race", seq: 1, epoch }

      const [a, b] = await Promise.all([
        alice.acknowledge(row.nonce, ack),
        alice.acknowledge(row.nonce, ack),
      ])
      expect(a?.plaintext).toBe("race")
      expect(b?.plaintext).toBe("race")
      expect(await alice.pendingOutbox(BOB)).toEqual([])
      expect((await alice.history(BOB)).map((h) => h.id)).toEqual(["m-race"])
    })

    it("resends a pending row unchanged within the same epoch", async () => {
      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "pending", epoch)

      await alice.flushOutbox(BOB)
      expect(server.messages).toHaveLength(1)
      expect(server.messages[0].client_nonce).toBe(row.nonce)
      expect(await alice.pendingOutbox(BOB)).toEqual([])
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["pending"])
    })

    it("does not duplicate a message when the send is retried", async () => {
      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "retry", epoch)
      await alice.deliver({ ...row })
      await alice.deliver({ ...row })
      expect(server.messages).toHaveLength(1)
    })

    it("re-encrypts a pending row with a new nonce after an epoch change", async () => {
      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "stale", epoch)
      server.rotateEpoch(ALICE, BOB)

      await alice.flushOutbox(BOB)
      expect(server.messages).toHaveLength(1)
      expect(server.messages[0].client_nonce).not.toBe(row.nonce)
      expect(server.messages[0].type).toBe(3)
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["stale"])
    })

    it("delivers a stale row once when flushes overlap", async () => {
      const epoch = await alice.openConversation()
      await alice.encryptMessage(BOB, "once", epoch)
      server.rotateEpoch(ALICE, BOB)

      await Promise.all([alice.flushOutbox(BOB), alice.flushOutbox(BOB)])
      expect(server.messages).toHaveLength(1)
      expect(await alice.pendingOutbox(BOB)).toEqual([])
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["once"])
    })

    it("rebuilds the session on stale_epoch replies", async () => {
      await alice.send(BOB, "old epoch")
      await receiveAll(server, bob, BOB, ALICE)
      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "racing", epoch)
      server.rotateEpoch(ALICE, BOB)

      const delivered = await alice.deliver(row)
      expect(delivered?.epoch).not.toBe(epoch)
      expect(server.messages.at(-1).type).toBe(3)
      expect((await receiveAll(server, bob, BOB, ALICE)).at(-1)).toBe("racing")
    })

    it("decrypts the new PreKey message after a server restart reuses seqs", async () => {
      await alice.send(BOB, "before restart")
      await receiveAll(server, bob, BOB, ALICE)

      server.messages = []
      server.nonces.clear()
      server.seq = 0
      server.rotateEpoch(ALICE, BOB)

      await alice.send(BOB, "after restart")
      const [message] = server.inbox(BOB, ALICE)
      expect(message.seq).toBe(1)
      expect(await bob.decryptMessage(ALICE, message)).toBe("after restart")
      expect((await bob.history(ALICE)).map((h) => h.plaintext)).toEqual([
        "before restart",
        "after restart",
      ])
    })

    it("catches up over several pages, skipping known messages by id", async () => {
      server.pageSize = 2
      await alice.send(BOB, "1")
      await receiveAll(server, bob, BOB, ALICE)
      for (const text of ["2", "3", "4", "5"]) await alice.send(BOB, text)

      const epoch = server.currentEpoch(ALICE, BOB)
      await bob.catchUp(ALICE, epoch)
      expect((await bob.history(ALICE)).map((h) => h.plaintext)).toEqual(["1", "2", "3", "4", "5"])
      expect(await bob.cursor(ALICE)).toEqual({ epoch, lastSeq: 5 })
    })

    it("stops catching up at the first message rendered by the server", async () => {
      for (const text of ["1", "2", "3"]) await alice.send(BOB, text)
      const epoch = server.currentEpoch(ALICE, BOB)
      await bob.catchUp(ALICE, epoch, 3)
      expect((await bob.history(ALICE)).map((h) => h.plaintext)).toEqual(["1", "2"])
    })

    it("shows the same safety number on both sides", async () => {
      await alice.send(BOB, "hi")
      await receiveAll(server, bob, BOB, ALICE)
      const a = await alice.safetyNumber(BOB)
      const b = await bob.safetyNumber(ALICE)
      expect(a).toMatch(/^\d{60}$/)
      expect(a).toBe(b)
    })

    it("clears the local history of a conversation", async () => {
      await alice.send(BOB, "gone")
      await alice.clearHistory(BOB)
      expect(await alice.history(BOB)).toEqual([])
    })
  })

  describe("identity changes", () => {
    it("blocks a changed peer identity until approved, then rebuilds", async () => {
      const alice = (await device(server, ALICE, BOB)).client
      const bob = (await device(server, BOB, ALICE)).client
      await alice.ensureKeys()
      await bob.ensureKeys()
      await alice.send(BOB, "hello")
      await receiveAll(server, bob, BOB, ALICE)

      // Bob moves to a new device.
      const bob2 = (await device(server, BOB, ALICE)).client
      expect(await bob2.ensureKeys()).toBe("needs_reset")
      await bob2.resetIdentity()

      // Alice's sessions stay bound to the old identity until she approves.
      server.rotateEpoch(ALICE, BOB)
      await expect(alice.send(BOB, "to new device")).rejects.toThrow(IdentityChangedError)
      expect(await alice.pendingIdentity(BOB)).toBeDefined()

      await alice.approveIdentity(BOB)
      expect(await alice.pendingIdentity(BOB)).toBeUndefined()
      await alice.flushOutbox(BOB)
      await alice.send(BOB, "approved")
      const inbox = server.inbox(BOB, ALICE).slice(1)
      const plaintexts = []
      for (const m of inbox) plaintexts.push(await bob2.decryptMessage(ALICE, m))
      expect(plaintexts.at(-1)).toBe("approved")
    })

    it("refuses a PreKey message from a changed identity (processV3 regression)", async () => {
      const alice = (await device(server, ALICE, BOB)).client
      const bob = (await device(server, BOB, ALICE)).client
      await alice.ensureKeys()
      await bob.ensureKeys()
      await alice.send(BOB, "hello")
      await receiveAll(server, bob, BOB, ALICE)

      const alice2 = (await device(server, ALICE, BOB)).client
      await alice2.ensureKeys()
      await alice2.resetIdentity()
      server.rotateEpoch(ALICE, BOB)
      await alice2.send(BOB, "impostor?")

      const message = server.inbox(BOB, ALICE).at(-1)
      await expect(bob.decryptMessage(ALICE, message)).rejects.toThrow(IdentityChangedError)
      expect(await bob.historyEntry(message.id)).toBeUndefined()

      await bob.approveIdentity(ALICE)
      expect(await bob.decryptMessage(ALICE, message)).toBe("impostor?")
    })

    it("re-encrypts pending rows after an own identity reset", async () => {
      const alice = (await device(server, ALICE, BOB)).client
      const bob = (await device(server, BOB, ALICE)).client
      await alice.ensureKeys()
      await bob.ensureKeys()

      const epoch = await alice.openConversation()
      const row = await alice.encryptMessage(BOB, "queued", epoch)
      await alice.resetIdentity()

      await alice.flushOutbox(BOB)
      expect(server.messages).toHaveLength(1)
      expect(server.messages[0].client_nonce).not.toBe(row.nonce)
      expect(await receiveAll(server, bob, BOB, ALICE)).toEqual(["queued"])
    })

    it("serializes an encryption requested during an identity reset", async () => {
      const alice = (await device(server, ALICE, BOB)).client
      await alice.ensureKeys()
      await (await device(server, BOB, ALICE)).client.ensureKeys()
      const epoch = await alice.openConversation()

      let release = () => {}
      server.intercept.set("signal_status", () => {
        server.intercept.delete("signal_status")
        return new Promise((resolve) => {
          release = () => resolve(server.handle(ALICE, BOB, "signal_status", {}))
        })
      })

      const reset = alice.resetIdentity()
      await new Promise((r) => setTimeout(r, 10))
      const encrypt = alice.encryptMessage(BOB, "during reset", epoch)
      release()
      await reset
      // The encryption ran after the reset completed, with the new identity.
      const row = await encrypt
      expect(row.identityKey).toBe(await alice.identityKey())
    })
  })

  describe("device lifecycle", () => {
    it("isolates the stores of different sessions in the same browser", async () => {
      const factory = new IDBFactory()
      const one = (await device(server, ALICE, BOB, { factory })).client
      await one.ensureKeys()
      const other = (await device(server, 3, BOB, { factory })).client
      await other.ensureKeys()
      expect(await one.identityKey()).not.toBe(await other.identityKey())
      expect(server.bundles.get(ALICE).identity_key).toBe(await one.identityKey())
    })

    it("forgets the device by deleting its database", async () => {
      const { client, factory } = await device(server, ALICE, BOB)
      await client.ensureKeys()
      await client.forgetDevice()
      const names = (await factory.databases()).map((d) => d.name)
      expect(names).not.toContain(dbNameFor(ALICE))
    })

    it("keeps the database when the client is merely closed (logout)", async () => {
      const { client, factory } = await device(server, ALICE, BOB)
      await client.ensureKeys()
      const identity = await client.identityKey()
      client.close()
      const reopened = (await device(server, ALICE, BOB, { factory })).client
      expect(await reopened.identityKey()).toBe(identity)
    })
  })
})
