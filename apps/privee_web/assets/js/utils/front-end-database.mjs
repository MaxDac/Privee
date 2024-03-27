const dbName = "SessionDatabase"
const tableName = "keys"

/**
 * @typedef {"ok" | "error" | "blocked" | "upgradeneeded"} DbOperationResult
 */

/**
  * Stores the object in the IndexedDB of the browser with the given key.
  * @template T The type of the object stored in the IndexedDB.
  * @param {string} key The key.
  * @param {T} item The item that will be stored in the IndexedDB.
  * @returns {Promise<void>} The asynchronous result.
  */
export const storeObject = (key, item) =>
  new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName)

    request.onupgradeneeded = () => {
      const db = request.result
      db.createObjectStore(tableName)
    }

    request.onsuccess = () => {
      const db = request.result
      const transaction = db.transaction(tableName, "readwrite")
      const keyStore = transaction.objectStore(tableName)
      keyStore.add(item, key)
      resolve()
    }

    request.onerror = reject
  })

/**
 * Performs an operation on the IndexedDB.
 * @template T The return type.
 * @param {(keyStore: IDBObjectStore) => IDBRequest<T>} operation The operation to perform on the DB KeyStore.
 * @returns {Promise<T>} The result of the operation.
 */
const requestOperationFromDb = (operation) =>
  indexedDB.databases()
    .then(dbs => {
      return new Promise((resolve, reject) => {
        if (dbs.some(db => db.name === dbName)) {
          const dbRequest = indexedDB.open(dbName)

          dbRequest.onsuccess = () => {
            const keyStore = dbRequest.result
              .transaction(tableName, "readwrite")
              .objectStore(tableName)

            const request = operation(keyStore)

            // @ts-ignore
            request.onsuccess = r => resolve(r.target.result)
            request.onerror = e => {
              reject(e)
            }
          }

          dbRequest.onerror = e => {
            reject(e)
          }
        } else {
          reject("There are no databases with the given name.")
        }
      })
    })

/**
  * Fetches the object from the IndexedDB in the browser correspondent to the
  * given key.
  * @template T The type of the object stored in the IndexedDB.
  * @param {string} key The database key.
  * @returns {Promise<T>} The object stored in the IndexedDB.
  */
export const getObject = key =>
  requestOperationFromDb(keyStore => keyStore.get(key))

/**
 * Removes an item with the given key from the IndexedDB.
 * @param {string} key The object key.
 * @returns {Promise<Event>} The deletion result.
 */
export const deleteObject = key =>
  requestOperationFromDb(keyStore => keyStore.delete(key))

/**
 * Purges the database, removing all the data stored in the IndexedDB.
 * @returns {Promise<Event>} The result of the deletion operation.
 */
export const purgeDatabase = () => 
  requestOperationFromDb(keyStore => keyStore.clear())

/**
 * Deletes the key database from the browser.
 * This function is currently untested, as it's timeouting without a known reason.
 * @returns {Promise<[DbOperationResult, Event]>} The result of the deletion operation.
 */
export const tryDeleteDatabase = () => 
  new Promise((resolve, _reject) => {
    const request = indexedDB.deleteDatabase(dbName)

    request.onsuccess = e => resolve(["ok", e])
    request.onerror = e => resolve(["error", e])
    request.onblocked = e => resolve(["blocked", e]) 
    request.onupgradeneeded = e => resolve(["upgradeneeded", e])
  })
