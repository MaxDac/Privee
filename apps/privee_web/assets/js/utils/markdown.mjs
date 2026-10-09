/**
 * Minimal, safe inline markdown for chat messages (#62).
 *
 * Supported: `code`, **bold**, *italic* / _italic_, ~~strikethrough~~ and
 * http(s) links. The result is built from DOM nodes and text nodes only, never
 * from HTML strings, so message content cannot inject markup.
 */

/**
 * @typedef {object} Rule
 * @property {RegExp} re
 * @property {"code" | "strong" | "em" | "s" | "a"} tag
 */

/** @type {Rule[]} Earlier rules win when two matches start at the same index. */
const rules = [
  { re: /`([^`\n]+)`/, tag: "code" },
  { re: /\bhttps?:\/\/[^\s<>"]*[^\s<>".,;:!?)\]'*_~`]/, tag: "a" },
  { re: /\*\*(\S(?:.*?\S)?)\*\*/, tag: "strong" },
  { re: /~~(\S(?:.*?\S)?)~~/, tag: "s" },
  { re: /(?<![\w*])\*(\S(?:.*?\S)?)\*(?![\w*])/, tag: "em" },
  { re: /(?<!\w)_(\S(?:.*?\S)?)_(?!\w)/, tag: "em" },
]

/**
 * @param {string} text
 * @returns {{rule: Rule, match: RegExpExecArray} | null}
 */
const firstMatch = (text) => {
  /** @type {{rule: Rule, match: RegExpExecArray} | null} */
  let best = null
  for (const rule of rules) {
    const match = rule.re.exec(text)
    if (match && (!best || match.index < best.match.index)) best = { rule, match }
  }
  return best
}

/**
 * @param {Document} doc
 * @param {string} href
 * @returns {HTMLElement | Text}
 */
const link = (doc, href) => {
  let url
  try {
    url = new URL(href)
  } catch {
    return doc.createTextNode(href)
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return doc.createTextNode(href)

  const a = doc.createElement("a")
  a.href = url.href
  a.target = "_blank"
  a.rel = "noopener noreferrer nofollow"
  a.className = "underline underline-offset-2 break-all"
  a.textContent = href
  return a
}

/**
 * @param {Document} doc
 * @param {string} text
 * @param {number} depth
 * @returns {Node[]}
 */
const parse = (doc, text, depth) => {
  /** @type {Node[]} */
  const nodes = []
  let rest = text

  while (rest) {
    const found = depth < 8 ? firstMatch(rest) : null
    if (!found) {
      nodes.push(doc.createTextNode(rest))
      break
    }

    const { rule, match } = found
    if (match.index > 0) nodes.push(doc.createTextNode(rest.slice(0, match.index)))

    if (rule.tag === "a") {
      nodes.push(link(doc, match[0]))
    } else {
      const el = doc.createElement(rule.tag)
      if (rule.tag === "code") {
        el.className = "rounded bg-black/10 px-1 font-mono text-[0.9em]"
        el.textContent = match[1]
      } else {
        el.append(...parse(doc, match[1], depth + 1))
      }
      nodes.push(el)
    }

    rest = rest.slice(match.index + match[0].length)
  }

  return nodes
}

/**
 * Renders a message as a fragment of safe DOM nodes.
 * @param {Document} doc
 * @param {string} text
 * @returns {DocumentFragment}
 */
export const renderMarkdown = (doc, text) => {
  const fragment = doc.createDocumentFragment()
  fragment.append(...parse(doc, text, 0))
  return fragment
}
