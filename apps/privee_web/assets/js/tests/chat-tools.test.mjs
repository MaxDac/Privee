import { JSDOM } from "jsdom"
import { describe, it, expect } from "vitest"
import { renderMarkdown } from "../utils/markdown.mjs"
import {
  csvCell,
  hashPassword,
  historyToCsv,
  parseCommand,
  suggestCommands,
} from "../utils/commands.mjs"
import { VimMode } from "../utils/vim.mjs"

const doc = () => new JSDOM("<body></body>").window.document

/** @param {string} text */
const html = (text) => {
  const d = doc()
  const div = d.createElement("div")
  div.append(renderMarkdown(d, text))
  return div
}

describe("renderMarkdown", () => {
  it("renders inline formatting with DOM nodes", () => {
    const el = html("**bold** *it* _it2_ ~~gone~~ `x < y` plain")
    expect(el.querySelector("strong")?.textContent).toBe("bold")
    expect([...el.querySelectorAll("em")].map((e) => e.textContent)).toEqual(["it", "it2"])
    expect(el.querySelector("s")?.textContent).toBe("gone")
    expect(el.querySelector("code")?.textContent).toBe("x < y")
    expect(el.textContent).toBe("bold it it2 gone x < y plain")
  })

  it("nests formatting but not inside code", () => {
    const el = html("**bold _and italic_** `**raw**`")
    expect(el.querySelector("strong em")?.textContent).toBe("and italic")
    expect(el.querySelector("code")?.textContent).toBe("**raw**")
  })

  it("never interprets HTML", () => {
    const el = html("<img src=x onerror='alert(1)'> <script>x</script> **<b>y</b>**")
    expect(el.querySelector("img, script, b")).toBeNull()
    expect(el.querySelector("strong")?.textContent).toBe("<b>y</b>")
  })

  it("links only http(s) URLs, opened safely", () => {
    const el = html("go to https://example.com/a?b=1. not javascript:alert(1) or ftp://x")
    const links = el.querySelectorAll("a")
    expect(links).toHaveLength(1)
    expect(links[0].href).toBe("https://example.com/a?b=1")
    expect(links[0].target).toBe("_blank")
    expect(links[0].rel).toBe("noopener noreferrer nofollow")
    expect(el.textContent).toBe(
      "go to https://example.com/a?b=1. not javascript:alert(1) or ftp://x",
    )
  })

  it("leaves snake_case and lone markers alone", () => {
    expect(html("snake_case_name 2 * 3 * 4").children).toHaveLength(0)
  })
})

describe("commands", () => {
  it("parses known commands only", () => {
    expect(parseCommand(":lock  my secret ")).toEqual({ name: "lock", arg: "my secret" })
    expect(parseCommand(":export")).toEqual({ name: "export", arg: "" })
    expect(parseCommand(":D")).toBeNull()
    expect(parseCommand(":unknown")).toBeNull()
    expect(parseCommand("hello :lock")).toBeNull()
  })

  it("suggests commands while typing the name", () => {
    expect(suggestCommands(":").length).toBeGreaterThan(5)
    expect(suggestCommands(":un").map((c) => c.name)).toEqual(["unlock"])
    expect(suggestCommands(":lock ")).toEqual([])
    expect(suggestCommands("lock")).toEqual([])
  })

  it("hashes passwords with a salt", async () => {
    const first = await hashPassword("pw")
    const again = await hashPassword("pw", first.salt)
    expect(again.hash).toBe(first.hash)
    expect((await hashPassword("pw")).hash).not.toBe(first.hash)
    expect((await hashPassword("other", first.salt)).hash).not.toBe(first.hash)
  })

  it("escapes CSV and neutralizes formulas", () => {
    expect(csvCell("plain")).toBe("plain")
    const q = String.fromCharCode(34)
    expect(csvCell(`a,${q}b${q}`)).toBe(`${q}a,${q}${q}b${q}${q}${q}`)
    for (const prefix of ["=", "+", "-", "@", "\t"])
      expect(csvCell(`${prefix}1`)).toBe(`'${prefix}1`)
    expect(csvCell("line\r\nbreak")).toBe(`${q}line\r\nbreak${q}`)
  })

  it("exports history rows sorted by time", () => {
    const csv = historyToCsv([
      /** @type {any} */ ({ ts: 2000, direction: "in", plaintext: "b" }),
      /** @type {any} */ ({ ts: 1000, direction: "out", plaintext: "a" }),
      /** @type {any} */ ({ ts: 3000, direction: "in", plaintext: null }),
    ])
    expect(csv).toBe(
      "timestamp,direction,message\r\n" +
        "1970-01-01T00:00:01.000Z,sent,a\r\n" +
        "1970-01-01T00:00:02.000Z,received,b\r\n" +
        "1970-01-01T00:00:03.000Z,received,\r\n",
    )
  })
})

describe("VimMode", () => {
  const setup = (value = "") => {
    const d = doc()
    const input = d.createElement("input")
    const indicator = d.createElement("span")
    d.body.append(input, indicator)
    input.value = value
    input.setSelectionRange(value.length, value.length)
    const store = new Map()
    const storage = /** @type {Storage} */ (
      /** @type {unknown} */ ({
        getItem: (k) => store.get(k) ?? null,
        setItem: (k, v) => store.set(k, v),
        removeItem: (k) => store.delete(k),
      })
    )
    const vim = new VimMode(input, { indicator, storage })
    /** @param {string} key */
    const press = (key) => {
      const event = new d.defaultView.KeyboardEvent("keydown", { key, cancelable: true })
      input.dispatchEvent(event)
      return event.defaultPrevented
    }
    return { input, indicator, vim, press, storage }
  }

  it("is off by default and remembers the choice", () => {
    const { vim, indicator, press, storage, input } = setup("hello")
    expect(indicator.hidden).toBe(true)
    expect(press("x")).toBe(false)
    vim.toggle()
    expect(storage.getItem("privee:vim")).toBe("1")
    expect(indicator.hidden).toBe(false)
    expect(indicator.textContent).toBe("-- INSERT --")
    expect(new VimMode(input, { storage }).enabled).toBe(true)
  })

  it("moves and edits in normal mode", () => {
    const { vim, input, indicator, press } = setup("hello brave world")
    vim.toggle()
    press("Escape")
    expect(indicator.textContent).toBe("-- NORMAL --")
    expect(input.dataset.vimMode).toBe("normal")

    press("0")
    expect(input.selectionStart).toBe(0)
    press("w")
    expect(input.selectionStart).toBe(6)
    press("e")
    expect(input.selectionStart).toBe(10)
    press("b")
    expect(input.selectionStart).toBe(6)
    press("x")
    expect(input.value).toBe("hello rave world")
    expect(press("q")).toBe(true)
    expect(input.value).toBe("hello rave world")

    press("A")
    expect(input.dataset.vimMode).toBe("insert")
    expect(input.selectionStart).toBe(input.value.length)
    expect(press("z")).toBe(false)

    press("Escape")
    press("d")
    press("d")
    expect(input.value).toBe("")
  })

  it("lets Enter through to send in normal mode", () => {
    const { vim, press } = setup("hi")
    vim.toggle()
    press("Escape")
    expect(press("Enter")).toBe(false)
  })
})
