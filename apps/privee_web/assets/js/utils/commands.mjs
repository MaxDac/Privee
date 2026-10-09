/**
 * Chat commands typed in the composer, such as `:lock secret` (#72, #73).
 *
 * Commands run in the browser only and are never sent to the server: with
 * end-to-end encryption the server cannot read messages, so it cannot interpret
 * them either. Text that does not match a known command is sent as a message,
 * except a mistyped command (`:lok`); `::` sends a literal leading colon.
 */

/** @typedef {"lock" | "unlock" | "export" | "clear" | "safety" | "hint" | "vim"} CommandName */

/**
 * @typedef {object} Command
 * @property {CommandName} name
 * @property {string} textKey Client text describing the command.
 * @property {boolean} [arg] Whether the command takes an argument.
 */

/** @type {readonly Command[]} */
export const Commands = Object.freeze([
  { name: "lock", textKey: "commandLock", arg: true },
  { name: "unlock", textKey: "commandUnlock", arg: true },
  { name: "export", textKey: "commandExport" },
  { name: "safety", textKey: "commandSafety" },
  { name: "hint", textKey: "commandHint" },
  { name: "clear", textKey: "commandClear" },
  { name: "vim", textKey: "commandVim" },
])

/**
 * @param {string} text
 * @returns {{name: CommandName, arg: string} | null}
 */
export const parseCommand = (text) => {
  const match = /^:([a-z]+)(?:\s+([\s\S]*))?$/.exec(text.trim())
  if (!match) return null
  const command = Commands.find((c) => c.name === match[1])
  return command ? { name: command.name, arg: match[2]?.trim() ?? "" } : null
}

/**
 * Whether the text looks like a command that does not exist (`:lok secret`).
 * It is not sent, so a mistyped command never reaches the peer.
 * @param {string} text
 */
export const isUnknownCommand = (text) =>
  /^:[a-z]+(?:\s|$)/.test(text.trim()) && parseCommand(text) === null

/**
 * The message to send for a composer text: a leading `::` sends a literal
 * leading colon (`::lock` sends `:lock`).
 * @param {string} text
 */
export const messageText = (text) => (text.startsWith("::") ? text.slice(1) : text)

/**
 * Commands to suggest while the user is typing the command name.
 * @param {string} text
 * @returns {Command[]}
 */
export const suggestCommands = (text) => {
  const match = /^:([a-z]*)$/.exec(text)
  if (!match) return []
  return Commands.filter((c) => c.name.startsWith(match[1]))
}

/**
 * Hashes a lock password with a random salt. Only the hash stays in memory.
 * @param {string} password
 * @param {Uint8Array} [salt]
 * @returns {Promise<{salt: Uint8Array, hash: string}>}
 */
export const hashPassword = async (password, salt = crypto.getRandomValues(new Uint8Array(16))) => {
  const data = new Uint8Array([...salt, ...new TextEncoder().encode(password)])
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data))
  return { salt, hash: Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("") }
}

/**
 * Escapes a CSV cell and neutralizes spreadsheet formulas (CSV injection).
 * @param {string} value
 * @returns {string}
 */
export const csvCell = (value) => {
  const safe = /^\s*[=+\-@|]/.test(value) || /^[\t\r]/.test(value) ? `'${value}` : value
  return /[",\r\n]/.test(safe) ? `"${safe.replace(/"/g, (quote) => quote + quote)}"` : safe
}

/**
 * @param {import("./signal-client.mjs").HistoryRow[]} rows
 * @returns {string}
 */
export const historyToCsv = (rows) =>
  [
    ["timestamp", "direction", "message"],
    ...[...rows]
      .sort((a, b) => a.ts - b.ts)
      .map((row) => [
        new Date(row.ts).toISOString(),
        row.direction === "out" ? "sent" : "received",
        row.plaintext ?? "",
      ]),
  ]
    .map((cells) => cells.map(csvCell).join(","))
    .join("\r\n") + "\r\n"
