module.exports = {
  env: {
    browser: true,
    node: true,
    es2021: true,
  },
  plugins: ["jsdoc", "prettier"],
  extends: ["eslint:recommended", "plugin:prettier/recommended"],
  overrides: [
    {
      env: {
        node: true,
      },
      files: [".eslintrc.{js,cjs}"],
      parserOptions: {
        sourceType: "script",
      },
    },
    {
      env: {
        node: true,
      },
      files: ["**/*.mjs"],
      parserOptions: {
        sourceType: "module",
      },
    },
  ],
  parserOptions: {
    ecmaVersion: "latest",
    sourceType: "module",
  },
  ignorePatterns: ["**/types/**/*.d.ts", "**/*.cjs"],
  parser: "@typescript-eslint/parser",
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
    "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    "require-await": "error",
  },
}
