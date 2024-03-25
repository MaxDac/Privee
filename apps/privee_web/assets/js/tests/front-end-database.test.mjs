import test from "ava"
import { indexedDB } from "fake-indexeddb"
import { storeObject, getObject } from "../utils/front-end-database.mjs"

test("storeObject stores the object", async t => {
  global.indexedDB = indexedDB

  const object = {a: 1, b: "2"}
  await storeObject("test", object)
    .then(() => t.pass())
    .catch(e => t.fail(String(e)))
})

test("getObject retrieves the object given the proper key", async t => {
  global.indexedDB = indexedDB

  const object = {a: 1, b: "2"}
  await storeObject("test", object)

  const retrievedObject = await getObject("test")
  t.deepEqual(retrievedObject, object)
})

test("getObject returns null if key does not exist", async t => {
  global.indexedDB = indexedDB

  const retrievedObject = await getObject("nonexistent")
  t.is(retrievedObject, undefined)
})