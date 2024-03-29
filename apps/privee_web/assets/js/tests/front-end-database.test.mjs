import { test, describe, it, expect } from "vitest"
import { indexedDB } from "fake-indexeddb"
import {
  storeObject,
  getObject,
  deleteObject,
  purgeDatabase,
} from "../utils/front-end-database.mjs"

describe("getObject", () => {
  it("returns undefined if the database does not exist", async () => {
    global.indexedDB = indexedDB

    try {
      await getObject("test")
      expect.fail()
    } catch (e) {
      expect(e).toBe("There are no databases with the given name.")
    }
  })

  it("retrieves the object given the proper key", async () => {
    global.indexedDB = indexedDB

    const object = { a: 1, b: "2" }
    await storeObject("test", object)

    const retrievedObject = await getObject("test")
    expect(retrievedObject).toStrictEqual(object)
    expect(retrievedObject).toStrictEqual(object)
  })

  it("getObject returns null if key does not exist", async () => {
    global.indexedDB = indexedDB

    const retrievedObject = await getObject("nonexistent")
    expect(retrievedObject).toBe(undefined)
  })
})

test("storeObject stores the object", async () => {
  global.indexedDB = indexedDB

  const object = { a: 1, b: "2" }
  await storeObject("test", object).catch((e) => expect.fail(JSON.stringify(e)))
})

test("deleteObject removes the object with the given key", async () => {
  global.indexedDB = indexedDB

  const object = { a: 1, b: "2" }
  await storeObject("test", object)

  await deleteObject("test")
    .then(() => getObject("test"))
    .then((retrievedObject) => {
      expect(retrievedObject).toBe(undefined)
    })
    .catch((e) => expect.fail(JSON.stringify(e)))
})

test("purgeDatabase removes all data from the IndexedDB", async () => {
  global.indexedDB = indexedDB

  const object1 = { a: 1, b: "2" }
  const object2 = { c: 3, d: "4" }

  await storeObject("test1", object1)
  await storeObject("test2", object2)

  await purgeDatabase()
    .then(() => getObject("test1"))
    .then((retrievedObject) => {
      expect(retrievedObject).toBe(undefined)
    })
    .then(() => getObject("test2"))
    .then((retrievedObject) => {
      expect(retrievedObject).toBe(undefined)
    })
    .catch((e) => expect.fail(JSON.stringify(e)))
})
