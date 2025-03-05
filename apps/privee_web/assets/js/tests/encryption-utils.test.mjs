import { describe, it, expect } from "vitest"
import { arrayDataToString, stringToArrayData } from "../utils/encryption-utils.mjs"

describe("stringToArrayData", () => {
  it("should convert a string to an ArrayBuffer base64 representation", () => {
    const input = "Hello, World!"
    const expected = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33])
      .buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })

  it("should return an empty array if passed an empty string", () => {
    const input = ""
    const expected = new Uint8Array([]).buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })

  it("should return an empty array if passed null", () => {
    const input = null
    const expected = new Uint8Array([]).buffer
    const result = stringToArrayData(input)
    expect(result).toStrictEqual(expected)
  })
})

describe("arrayDataToString", () => {
  it("should convert an ArrayBuffer to a string", () => {
    const input = new Uint8Array([72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33])
      .buffer
    const expected = "Hello, World!"
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })

  it("should convert an empty array to a string", () => {
    const input = new Uint8Array([]).buffer
    const expected = ""
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })

  it("should convert null to an empty string", () => {
    const input = null
    const expected = ""
    const result = arrayDataToString(input)
    expect(result).toStrictEqual(expected)
  })
})

describe("text encryption", () => {
  it("should convert back a simple text", () => {
    const string = "Hello, World!"
    const encrypted = stringToArrayData(string)
    const decrypted = arrayDataToString(encrypted)

    expect(decrypted).toStrictEqual(string)
  })

  it("should convert back a text with accented letters", () => {
    const string = "Test with accented letters: áéíóú"
    const encrypted = stringToArrayData(string)
    const decrypted = arrayDataToString(encrypted)

    expect(decrypted).toStrictEqual(string)
  })
})
