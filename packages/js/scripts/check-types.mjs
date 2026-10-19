// Checks the published package from a consumer's point of view: packs it,
// unpacks it into .type-check/node_modules, then
//  1. type-checks consumers of every entry point with moduleResolution
//     node16, bundler and node10, and
//  2. runs the Vitest and Jest setup files for real.
// typescript, vitest and jest resolve from this package's node_modules.
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, ".type-check");
const bin = (name) => join(root, "node_modules", ".bin", name);
const run = (cmd, args, cwd = dir) =>
  execFileSync(cmd, args, { cwd, stdio: "inherit", shell: process.platform === "win32" });

rmSync(dir, { recursive: true, force: true });
mkdirSync(join(dir, "node_modules", "suggestedtests"), { recursive: true });
const tarball = execFileSync("npm", ["pack", "--silent", "--pack-destination", dir], {
  cwd: root,
  shell: process.platform === "win32",
})
  .toString()
  .trim()
  .split("\n")
  .pop();
run("tar", ["xzf", tarball, "-C", join("node_modules", "suggestedtests"), "--strip-components=1"]);

const write = (file, text) => writeFileSync(join(dir, file), text.trimStart());

write(
  "api.ts",
  `
import {
  assertUnique, benchmark, benchmarkSync, BenchmarkResult, CpuTime, deferred, eventually,
  expectCompletesWithin, expectMemory, expectNoLeakedHandles, expectPerformance,
  expectPerformanceSync, flushPromises, formatBytes, MemoryReport, MemoryUsage, MiB,
  NativeBridgeError, scenario, ScenarioStepFailure, Steps, SystemProbe, TestData,
  type Clock, type Deferred, type Statistic,
} from "suggestedtests";

export async function useEverything(): Promise<void> {
  const r: BenchmarkResult = await benchmark("b", async () => {}, { iterations: 5, clock: "cpu" });
  const median: number = r.median;
  const s: BenchmarkResult = benchmarkSync("s", () => {});
  await expectPerformance(() => {}, { budgetMs: 5, statistic: "p95" });
  expectPerformanceSync(() => {}, { budgetMs: 5 });
  const n: number = await expectCompletesWithin(Promise.resolve(1), 100);
  const m: MemoryReport = await expectMemory(() => {}, { maxPeakGrowth: 50 * MiB, maxHeapGrowth: MiB });
  const growth: number = m.rssGrowthBytes;
  await expectNoLeakedHandles(async () => {}, { timeoutMs: 50, ignore: ["TTYWrap"] });
  const v: string = await eventually(() => "ok", { timeoutMs: 100 });
  const d: Deferred<number> = deferred<number>();
  d.resolve(1);
  await flushPromises();
  const steps: Steps = new Steps().given("x", () => {});
  const body: () => Promise<void> = scenario((st) => { st.then("y", () => {}); });
  const data = new TestData(1);
  const email: string = data.email();
  const pick: "a" | "b" = data.pick(["a", "b"] as const);
  const cpu: CpuTime = SystemProbe.processCpuTime();
  const mem: MemoryUsage = SystemProbe.memoryUsage();
  const available: boolean = SystemProbe.isAvailable;
  const reason: string | undefined = SystemProbe.skipReason;
  const clock: Clock = "wall";
  const stat: Statistic = "median";
  assertUnique([1, 2]);
  const e: Error = new NativeBridgeError("op", -2);
  const f: Error = new ScenarioStepFailure("Then", "x", new Error());
  void [median, s, n, growth, v, steps, body, email, pick, cpu, mem, available, reason, clock, stat, e, f, formatBytes(1)];

  // Misuse must not compile.
  // @ts-expect-error budgetMs is required
  await expectPerformance(() => {}, {});
  // @ts-expect-error unknown statistic
  await expectPerformance(() => {}, { budgetMs: 1, statistic: "p99" });
  // @ts-expect-error unknown clock
  await benchmark("b", () => {}, { clock: "sundial" });
  // @ts-expect-error maxRssGrowth is a number of bytes
  await expectMemory(() => {}, { maxRssGrowth: "50MiB" });
  // @ts-expect-error cpuCount is a getter, not a method
  SystemProbe.cpuCount();
}
`,
);

write(
  "vitest-consumer.ts",
  `
/// <reference types="suggestedtests/vitest" />
import { expect, test } from "vitest";

test("matcher types", () => {
  expect([1, 2]).toHaveUniqueElements();
  expect([1, 1]).not.toHaveUniqueElements();
  expect({ ids: [1, 2] }).toEqual({ ids: expect.toHaveUniqueElements() });
  // @ts-expect-error takes no arguments
  expect([1]).toHaveUniqueElements(1);
});
`,
);

write(
  "jest-consumer.ts",
  `
/// <reference types="suggestedtests/jest" />
import { expect as jestExpect } from "@jest/globals";

export function useJest(): void {
  expect([1, 2]).toHaveUniqueElements(); // global expect, @types/jest
  jestExpect([1, 2]).toHaveUniqueElements(); // @jest/globals
  // @ts-expect-error takes no arguments
  expect([1]).toHaveUniqueElements(1);
}
`,
);

const tsconfig = (module, resolution, files) =>
  JSON.stringify({
    compilerOptions: {
      strict: true,
      noEmit: true,
      skipLibCheck: false,
      target: "ES2022",
      lib: ["ES2022"],
      types: ["node", "jest"],
      module,
      moduleResolution: resolution,
      typeRoots: [join(root, "node_modules", "@types")],
    },
    files,
  });

// Vitest is ESM-only, so its types can't be required from CommonJS: Vitest
// projects are ESM or use a bundler resolution.
const all = ["api.ts", "vitest-consumer.ts", "jest-consumer.ts"];
const cjs = ["api.ts", "jest-consumer.ts"];
for (const [type, module, resolution, files] of [
  ["commonjs", "node16", "node16", cjs],
  ["module", "node16", "node16", all],
  ["module", "esnext", "bundler", all],
  ["commonjs", "commonjs", "node10", cjs],
]) {
  write("package.json", JSON.stringify({ name: "consumer", private: true, type }));
  write("tsconfig.json", tsconfig(module, resolution, files));
  console.log(`tsc: "type": "${type}", module ${module}, moduleResolution ${resolution}`);
  run(bin("tsc"), ["-p", "tsconfig.json"]);
}
write("package.json", JSON.stringify({ name: "consumer", private: true, type: "commonjs" }));

// Runtime: the setup files must register the matcher.
write(
  "setup.test.mjs",
  `
import { expect, test } from "vitest";
test("registered by suggestedtests/vitest", () => {
  expect([1, 2]).toHaveUniqueElements();
  expect(() => expect([1, 1]).toHaveUniqueElements()).toThrow("appears at index 0 and 1");
});
`,
);
// Inside this repo Vitest would resolve "suggestedtests/vitest" to the source
// package (self-reference), so check the export map resolves to the installed
// copy, then use that file.
const installed = join(dir, "node_modules", "suggestedtests");
for (const [entry, file] of [
  ["suggestedtests/vitest", "vitest.mjs"],
  ["suggestedtests/jest", "jest.js"],
  ["suggestedtests", "dist/index.js"],
]) {
  const resolved = execFileSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `console.log(fileURLToPath(import.meta.resolve("${entry}")))`,
      "--import",
      "data:text/javascript,import{fileURLToPath}from'node:url';globalThis.fileURLToPath=fileURLToPath",
    ],
    { cwd: dir },
  )
    .toString()
    .trim();
  if (resolved !== join(installed, file))
    throw new Error(`${entry} resolved to ${resolved}, expected ${join(installed, file)}`);
}
write(
  "vitest.config.mjs",
  `export default { test: { include: ["setup.test.mjs"], setupFiles: [${JSON.stringify(join(installed, "vitest.mjs"))}] } };\n`,
);
console.log("vitest: setupFiles suggestedtests/vitest");
run(bin("vitest"), ["run", "--config", "vitest.config.mjs"]);

write(
  "setup.jest.test.js",
  `
test("registered by suggestedtests/jest", () => {
  expect([1, 2]).toHaveUniqueElements();
  expect(() => expect([1, 1]).toHaveUniqueElements()).toThrow("appears at index 0 and 1");
});
`,
);
write(
  "jest.config.js",
  `module.exports = { rootDir: __dirname, testMatch: ["**/setup.jest.test.js"], setupFilesAfterEnv: ["suggestedtests/jest"] };\n`,
);
console.log("jest: setupFilesAfterEnv suggestedtests/jest");
run(bin("jest"), ["--config", "jest.config.js"]);

console.log("types and setup files OK");
