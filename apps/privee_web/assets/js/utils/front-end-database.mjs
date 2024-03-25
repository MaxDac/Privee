const dbName = "SessionDatabase"
const tableName = "keys"

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
  * Fetches the object from the IndexedDB in the browser correspondent to the
  * given key.
  * @template T The type of the object stored in the IndexedDB.
  * @param {string} key The database key.
  * @returns {Promise<T>} The object stored in the IndexedDB.
  */
export const getObject = key =>
  new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName)

    request.onsuccess = () => {
      const db = request.result
      const transaction = db.transaction(tableName, "readwrite")
      const keyStore = transaction.objectStore(tableName)
      const getRequest = keyStore.get(key)

      // @ts-ignore
      getRequest.onsuccess = r => resolve(r.target.result)
      getRequest.onerror = reject
    }

    request.onerror = reject
  })

