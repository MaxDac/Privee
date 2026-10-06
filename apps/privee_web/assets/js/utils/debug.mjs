import { testExports } from "./security.mjs"

export const exportDebugFunctions = () => {
  // @ts-ignore
  window.stringToArrayData = testExports.stringToArrayData
  // @ts-ignore
  window.arrayDataToString = testExports.arrayDataToString
}
