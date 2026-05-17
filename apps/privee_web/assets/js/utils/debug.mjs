import { testExports } from "./signal-protocol.mjs"

export const exportDebugFunctions = () => {
  // @ts-ignore
  window.bufToBase64 = testExports.bufToBase64
  // @ts-ignore
  window.base64ToBuf = testExports.base64ToBuf
}
