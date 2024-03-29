import test from "ava"
import { indexedDB } from "fake-indexeddb"
import { storeObject, getObject, deleteObject, purgeDatabase } from "../utils/front-end-database.mjs"

test.serial("getObject returns undefined if the database does not exist", async (t) => {
  global.indexedDB = indexedDB

  try {
    await getObject("test")
  } catch (e) {
    t.is(e, "There are no databases with the given name.")
  }
})

test.serial("getObject retrieves the object given the proper key", async (t) => {
  global.indexedDB = indexedDB

  const object = { a: 1, b: "2" }
  await storeObject("test", object)

  const retrievedObject = await getObject("test")
  t.deepEqual(retrievedObject, object)
})

test.serial("getObject returns null if key does not exist", async (t) => {
  global.indexedDB = indexedDB

  const retrievedObject = await getObject("nonexistent")
  t.is(retrievedObject, undefined)
})

test.serial("storeObject stores the object", async (t) => {
  global.indexedDB = indexedDB

  const object = { a: 1, b: "2" }
  await storeObject("test", object)
    .then(() => t.pass())
    .catch((e) => t.fail(String(e)))
})

test.serial("deleteObject removes the object with the given key", async (t) => {
  global.indexedDB = indexedDB

  const object = { a: 1, b: "2" }
  await storeObject("test", object)

  await deleteObject("test")
    .then(() => getObject("test"))
    .then((retrievedObject) => {
      t.is(retrievedObject, undefined)
    })
    .catch((e) => t.fail(String(e)))
})

test.serial("purgeDatabase removes all data from the IndexedDB", async (t) => {
  global.indexedDB = indexedDB

  const object1 = { a: 1, b: "2" }
  const object2 = { c: 3, d: "4" }

  await storeObject("test1", object1)
  await storeObject("test2", object2)

  await purgeDatabase()
    .then(() => getObject("test1"))
    .then((retrievedObject) => {
      t.is(retrievedObject, undefined)
    })
    .then(() => getObject("test2"))
    .then((retrievedObject) => {
      t.is(retrievedObject, undefined)
    })
    .catch((e) => t.fail(String(e)))
})
