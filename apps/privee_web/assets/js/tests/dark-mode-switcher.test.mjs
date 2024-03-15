import test from "ava"
import { setStartupTheme } from "../utils/dark-mode-switcher.mjs"
import { documentMock, localStorageMock, windowMock } from "./mocks.mjs"

test.beforeEach(() => {
  global.localStorage = localStorageMock()
  // @ts-ignore
  global.window = windowMock
  // @ts-ignore
  global.document = documentMock
  // global.localStorage.setItem("color-theme", "light")

})

test("Browser switch to Dark mode when light mode was selected", t => {
  setStartupTheme()
  t.is(global.localStorage.getItem("color-theme"), "dark")
})