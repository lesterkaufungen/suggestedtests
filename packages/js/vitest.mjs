// Vitest setup file: registers the suggestedtests matchers.
//
//   // vitest.config.ts
//   export default defineConfig({ test: { setupFiles: ["suggestedtests/vitest"] } });
//
// Types: add `/// <reference types="suggestedtests/vitest" />` to a .d.ts file,
// or "suggestedtests/vitest" to compilerOptions.types.
import { createRequire } from "node:module";
import { expect } from "vitest";

// require, not import: loads the CommonJS build the same way whether or not
// Vite externalizes this package.
const { matchers } = createRequire(import.meta.url)("./dist/index.js");
expect.extend(matchers);
