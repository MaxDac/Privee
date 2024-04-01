/**
 * @typedef {"ok" | "error" | "blocked" | "upgradeneeded"} DbOperationResult
 */

/**
 * This type represents the object returned by the `openDb` function.
 * It contains the object store and the current transaction.
 * @typedef {object} IDBOpenedDatabase
 * @property {IDBTransaction} transaction The current transaction.
 * @property {IDBObjectStore} keyStore The object store of the IndexedDB.
 */

/**
 * Automatically opens a connection to the IndexedDB of the browser.
 * @param {string} dbName The name of the database.
 * @param {string} tableName The name of the table.
 * @returns {Promise<IDBOpenedDatabase>} The object store of the IndexedDB.
 */
const openDb = (dbName, tableName) => {
  const request = indexedDB.open(dbName)
  return new Promise((resolve, reject) => {
    request.onupgradeneeded = () => {
      const db = request.result
      db.createObjectStore(tableName)
    }

    request.onsuccess = () => {
      const db = request.result
      const transaction = db.transaction(tableName, "readwrite")
      const keyStore = transaction.objectStore(tableName)
      resolve({ transaction, keyStore })
    }

    request.onerror = (e) => {
      reject(e)
    }
  })
}

/**
 * Transforms an IndexedDB request into a promise.
 * @template T The type of the object stored in the IndexedDB.
 * @param {IDBOpenedDatabase} openedDb The object store of the IndexedDB.
 * @param {(objectStore: IDBObjectStore) => IDBRequest<T>} operation The IndexedDB request.
 * @returns {Promise<T>} The result of the request.
 */
const dbRequestToPromise = (openedDb, operation) =>
  new Promise((resolve, reject) => {
    const { transaction, keyStore } = openedDb
    const request = operation(keyStore)

    request.onsuccess = (e) => {
      transaction.commit()
      // @ts-ignore
      resolve(e.target.result)
    }

    request.onerror = (e) => {
      reject(e)
    }
  })

/**
 * Stores the object in the IndexedDB of the browser with the given key.
 * @template T The type of the object stored in the IndexedDB.
 * @param {string} dbName The name of the database.
 * @param {string} tableName The name of the table.
 * @param {string} key The key.
 * @param {T} item The item that will be stored in the IndexedDB.
 * @param {boolean} substituteOldest If `true`, the oldest item with the same key will be replaced.
 * @returns {Promise<IDBValidKey>} The operation result.
 */
export const storeObject = async (dbName, tableName, key, item, substituteOldest = true) => {
  const openedDb = await openDb(dbName, tableName)
  return await dbRequestToPromise(openedDb, (keyStore) =>
    substituteOldest ? keyStore.put(item, key) : keyStore.add(item, key),
  )
}

/**
 * Fetches the object from the IndexedDB in the browser correspondent to the
 * given key.
 * @template T The type of the object stored in the IndexedDB.
 * @param {string} dbName The name of the database.
 * @param {string} tableName The name of the table.
 * @param {string} key The database key.
 * @returns {Promise<?T>} The object stored in the IndexedDB.
 */
export const getObject = async (dbName, tableName, key) => {
  try {
    const openedDb = await openDb(dbName, tableName)
    return await dbRequestToPromise(openedDb, (keyStore) => keyStore.get(key))
  } catch (e) {
    return undefined
  }
}

/**
 * Removes an item with the given key from the IndexedDB.
 * @param {string} dbName The name of the database.
 * @param {string} tableName The name of the table.
 * @param {string} key The object key.
 * @returns {Promise<Event>} The deletion result.
 */
export const deleteObject = async (dbName, tableName, key) => {
  const openedDb = await openDb(dbName, tableName)
  return await dbRequestToPromise(openedDb, (keyStore) => keyStore.delete(key))
}

/**
 * Purges the database, removing all the data stored in the IndexedDB.
 * @param {string} dbName The name of the database.
 * @param {string} tableName The name of the table.
 * @returns {Promise<Event>} The result of the deletion operation.
 */
export const purgeDatabase = async (dbName, tableName) => {
  const openedDb = await openDb(dbName, tableName)
  return await dbRequestToPromise(openedDb, (keyStore) => keyStore.clear())
}

/**
 * Deletes the key database from the browser.
 * This function is currently untested, as it's timeouting without a known reason.
 * @param {string} dbName The name of the database.
 * @returns {Promise<[DbOperationResult, Event]>} The result of the deletion operation.
 */
export const tryDeleteDatabase = (dbName) =>
  new Promise((resolve, _reject) => {
    const request = indexedDB.deleteDatabase(dbName)

    request.onsuccess = (e) => resolve(["ok", e])
    request.onerror = (e) => resolve(["error", e])
    request.onblocked = (e) => resolve(["blocked", e])
    request.onupgradeneeded = (e) => resolve(["upgradeneeded", e])
  })
