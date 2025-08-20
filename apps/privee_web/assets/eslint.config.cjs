const { defineConfig, globalIgnores } = require("eslint/config")

const globals = require("globals")
const jsdoc = require("eslint-plugin-jsdoc")
const prettier = require("eslint-plugin-prettier")
const tsParser = require("@typescript-eslint/parser")
const js = require("@eslint/js")

const { FlatCompat } = require("@eslint/eslintrc")

const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
})

module.exports = defineConfig([
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
      },

      ecmaVersion: "latest",
      sourceType: "module",
      parserOptions: {},
      parser: tsParser,
    },

    plugins: {
      jsdoc,
      prettier,
    },

    extends: compat.extends("eslint:recommended", "plugin:prettier/recommended"),

    rules: {
      "prettier/prettier": ["error"],
      indent: ["error", 2],
      "linebreak-style": ["error", "unix"],
      quotes: ["error", "double"],
      semi: ["error", "never"],
      "jsdoc/check-types": "error",
      "jsdoc/valid-types": "error",
      "jsdoc/require-param-type": "error",
      "jsdoc/require-returns-type": "error",

      "no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
        },
      ],

      "require-await": "error",
    },
  },
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },

      sourceType: "script",
      parserOptions: {},
    },

    files: ["**/.eslintrc.{js,cjs}"],
  },
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },

      sourceType: "module",
      parserOptions: {},
    },

    files: ["**/*.mjs"],
  },
  globalIgnores(["**/types/**/*.d.ts", "**/*.cjs"]),
])
