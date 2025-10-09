import { describe, it, expect, vi, afterEach } from "vitest"
import { JSDOM } from "jsdom"
import { querySelectorArrayOf } from "../utils/dom-utils.mjs"

const html = `
  <p data-selector="0">One</p>
  <p data-selector="0">Two</p>
  <p data-selector="1">Three</p>
  <p data-selector="1">Four</p>
`

describe("querySelectorArrayOf", () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("Should return zero elements when the selector does not identify any element", () => {
    const selector = "#some-nonexistent-id"
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)

    const elements = querySelectorArrayOf(selector)

    expect(elements.length).toEqual(0)
  })

  it("Should return four elements when the selector identifies all elements", () => {
    const selector = "[data-selector]"
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)

    const elements = querySelectorArrayOf(selector)

    expect(elements.length).toEqual(4)
    expect(elements[0].textContent).toEqual("One")
    expect(elements[1].textContent).toEqual("Two")
    expect(elements[2].textContent).toEqual("Three")
    expect(elements[3].textContent).toEqual("Four")
  })

  it("Should return two elements when the selector identifies half elements", () => {
    // prettier-ignore
    const selector = "[data-selector=\"1\"]"
    const dom = new JSDOM(html)
    vi.stubGlobal("document", dom.window.document)

    const elements = querySelectorArrayOf(selector)

    expect(elements.length).toEqual(2)
    expect(elements[0].textContent).toEqual("Three")
    expect(elements[1].textContent).toEqual("Four")
  })
})
