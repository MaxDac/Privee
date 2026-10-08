/**
 * "Conversations on this browser": the local list of conversations of the
 * signed-in session, built from the peer metadata in IndexedDB, with the
 * local hint of each one. User text only reaches the DOM through `textContent`.
 */

import { clientText } from "./locale.mjs"

/**
 * @param {Document} doc
 * @param {number} ts
 */
const formatDate = (doc, ts) => {
  try {
    return new Intl.DateTimeFormat(doc.documentElement.lang || undefined, {
      dateStyle: "medium",
    }).format(new Date(ts))
  } catch {
    return new Date(ts).toLocaleDateString()
  }
}

/**
 * @param {Document} doc
 * @param {string} tag
 * @param {string} className
 */
const element = (doc, tag, className) => {
  const el = doc.createElement(tag)
  el.className = className
  return el
}

/**
 * Renders the list into `container`, replacing its content. Renders nothing
 * when there are no conversations.
 * @param {HTMLElement} container
 * @param {import("./peer-hints.mjs").Conversation[]} conversations
 * @param {{onEditHint: (conversation: import("./peer-hints.mjs").Conversation) => void}} handlers
 */
export const renderConversations = (container, conversations, { onEditHint }) => {
  const doc = container.ownerDocument
  container.replaceChildren()
  if (conversations.length === 0) return

  const section = element(doc, "section", "mt-10")
  section.id = "local-conversations-section"
  section.setAttribute("aria-labelledby", "local-conversations-title")

  const title = element(doc, "h2", "text-sm font-semibold text-zinc-800 dark:text-zinc-100")
  title.id = "local-conversations-title"
  title.dataset.clientText = "conversationsTitle"
  title.textContent = clientText("conversationsTitle", doc)

  const note = element(doc, "p", "mt-1 text-xs text-zinc-500")
  note.dataset.clientText = "conversationsNote"
  note.textContent = clientText("conversationsNote", doc)

  const list = element(
    doc,
    "ul",
    "mt-3 divide-y divide-zinc-200 overflow-hidden rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700",
  )
  list.id = "local-conversations-list"

  for (const conversation of conversations) {
    const item = element(
      doc,
      "li",
      "flex items-center gap-2 bg-white transition hover:bg-zinc-50 dark:bg-zinc-900 dark:hover:bg-zinc-800",
    )
    item.id = `conversation-${conversation.peerId}`
    item.dataset.peerId = String(conversation.peerId)

    const link = /** @type {HTMLAnchorElement} */ (
      element(doc, "a", "flex min-w-0 flex-1 flex-col px-4 py-3")
    )
    link.href = `/chat/${encodeURIComponent(conversation.name)}`
    link.dataset.phxLink = "redirect"
    link.dataset.phxLinkState = "push"

    const name = element(
      doc,
      "span",
      "truncate text-sm font-semibold text-zinc-900 dark:text-zinc-50",
    )
    name.dataset.role = "name"
    name.textContent = conversation.name
    link.append(name)

    if (conversation.hint) {
      const hint = element(doc, "span", "truncate text-xs italic text-zinc-600 dark:text-zinc-300")
      hint.dataset.role = "hint"
      hint.textContent = conversation.hint
      link.append(hint)
    }

    if (conversation.lastMessageAt) {
      const date = element(doc, "span", "text-[11px] text-zinc-400")
      date.dataset.role = "date"
      date.textContent = formatDate(doc, conversation.lastMessageAt)
      link.append(date)
    }

    const edit = /** @type {HTMLButtonElement} */ (
      element(
        doc,
        "button",
        "mr-3 shrink-0 rounded-full px-3 py-1 text-xs text-zinc-500 transition hover:bg-zinc-200 hover:text-zinc-800 active:scale-95 dark:hover:bg-zinc-700 dark:hover:text-zinc-200",
      )
    )
    edit.type = "button"
    edit.id = `conversation-${conversation.peerId}-hint`
    edit.dataset.clientText = "hintButton"
    edit.textContent = clientText("hintButton", doc)
    edit.addEventListener("click", () => onEditHint(conversation))

    item.append(link, edit)
    list.append(item)
  }

  section.append(title, note, list)
  container.append(section)
}
