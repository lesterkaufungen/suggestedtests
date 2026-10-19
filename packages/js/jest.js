// Jest setup file: registers the suggestedtests matchers.
//
//   // jest.config.js
//   module.exports = { setupFilesAfterEnv: ["suggestedtests/jest"] };
//
// Types: add `/// <reference types="suggestedtests/jest" />` to a .d.ts file,
// or "suggestedtests/jest" to compilerOptions.types.
"use strict";
const { matchers } = require("./dist/index.js");

if (typeof expect === "undefined") {
  throw new Error('suggestedtests/jest must be listed in Jest\'s "setupFilesAfterEnv"');
}
expect.extend(matchers);
