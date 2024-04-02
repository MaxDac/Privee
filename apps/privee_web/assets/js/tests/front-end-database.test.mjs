import { describe, it, expect, beforeEach } from "vitest"
import { indexedDB } from "fake-indexeddb"
import {
  storeObject,
  getObject,
  deleteObject,
  purgeDatabase,
} from "../utils/front-end-database.mjs"
import { generateRandomString } from "./mock-utils.mjs"

describe("DB Operations", () => {
  beforeEach(() => {
    global.indexedDB = indexedDB
    indexedDB.deleteDatabase("test")
  })

  describe("getObject", () => {
    it("returns undefined if the database does not exist", async () => {
      global.indexedDB = indexedDB
      const result = await getObject(generateRandomString(), generateRandomString(), "test")
      expect(result).toBeUndefined()
    })

    it("retrieves the object given the proper key", async () => {
      global.indexedDB = indexedDB

      const dbName = generateRandomString()
      const tableName = generateRandomString()

      const object = { a: 1, b: "2" }
      await storeObject(dbName, tableName, "test", object)

      const retrievedObject = await getObject(dbName, tableName, "test")
      expect(retrievedObject).toStrictEqual(object)
      expect(retrievedObject).toStrictEqual(object)
    })

    it("getObject returns null if key does not exist", async () => {
      global.indexedDB = indexedDB

      const retrievedObject = await getObject(
        generateRandomString(),
        generateRandomString(),
        "nonexistent",
      )
      expect(retrievedObject).toBe(undefined)
    })
  })

  describe("storeObject", () => {
    it("stores the object", async () => {
      global.indexedDB = indexedDB

      const object = { a: 1, b: "2" }

      try {
        await storeObject(generateRandomString(), generateRandomString(), "test", object)
      } catch (e) {
        expect.fail(e)
      }
    })

    it("stores the object, substituting the second object", async () => {
      global.indexedDB = indexedDB

      const dbName = generateRandomString()
      const tableName = generateRandomString()

      const firstObject = { a: 1, b: "2" }
      const secondObject = { a: 3, b: "4" }

      try {
        await storeObject(dbName, tableName, "test", firstObject)
        await storeObject(dbName, tableName, "test", secondObject)
      } catch (e) {
        expect.fail(e)
      }

      const storedObject = await getObject(dbName, tableName, "test")
      expect(storedObject).toStrictEqual(secondObject)
    })

    it("stores the first object, throwing an constraint exception when inserting the second", async () => {
      global.indexedDB = indexedDB

      const dbName = generateRandomString()
      const tableName = generateRandomString()

      const firstObject = { a: 1, b: "2" }
      const secondObject = { a: 3, b: "4" }

      try {
        await storeObject(dbName, tableName, "test", firstObject)
        await storeObject(dbName, tableName, "test", secondObject, false)
        expect.fail("The test should thrown an exception")
      } catch {
        /* test should thrown exception. */
      }

      const storedObject = await getObject(dbName, tableName, "test")
      expect(storedObject).toStrictEqual(firstObject)
    })
  })

  it("deleteObject removes the object with the given key", async () => {
    global.indexedDB = indexedDB
    const dbName = generateRandomString()
    const tableName = generateRandomString()

    const object = { a: 1, b: "2" }
    await storeObject(dbName, tableName, "test", object)

    try {
      await deleteObject(dbName, tableName, "test")
      const retrievedObject = await getObject(dbName, tableName, "test")
      expect(retrievedObject).toBe(undefined)
    } catch (e) {
      expect.fail(e)
    }
  })

  it("purgeDatabase removes all data from the IndexedDB", async () => {
    global.indexedDB = indexedDB

    const dbName = generateRandomString()
    const tableName = generateRandomString()

    const object1 = { a: 1, b: "2" }
    const object2 = { c: 3, d: "4" }

    await storeObject(dbName, tableName, "test1", object1)
    await storeObject(dbName, tableName, "test2", object2)

    try {
      await purgeDatabase(dbName, tableName)
      const retrievedObject = await getObject(dbName, tableName, "test1")

      expect(retrievedObject).toBe(undefined)

      await getObject(dbName, tableName, "test2")

      expect(retrievedObject).toBe(undefined)
    } catch (e) {
      expect.fail(JSON.stringify(e))
    }
  })
})
