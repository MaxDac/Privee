/**
 * Converts a string in base64 to an `ArrayBuffer.
 * @param {string} s The string to convert.
 * @returns {ArrayBuffer} The converted string.
 */
export const stringToArrayData = (s) => {
  if (!s) {
    return new ArrayBuffer(0)
  }

  const bufferView = new Uint8Array(s.length)

  for (let i = 0; i < s.length; i++) {
    bufferView[i] = s.charCodeAt(i)
  }

  return bufferView.buffer
}

/**
 * Converts an array buffer into a base64 string.
 * @param {ArrayBuffer} a The array buffer.
 * @returns {string} The converted string.
 */
export const arrayDataToString = (a) => String.fromCharCode.apply(null, new Uint8Array(a))
