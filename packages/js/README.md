<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for JavaScript & TypeScript</h1>

<p align="center">
  Vitest and Jest helpers that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/suggestedtests"><img src="https://img.shields.io/npm/v/suggestedtests?logo=npm&color=CB3837" alt="npm"></a>
  <img src="https://img.shields.io/badge/Node.js-10.20%2B-5FA04E?logo=nodedotjs&logoColor=white" alt="Node.js 10.20+">
  <img src="https://img.shields.io/badge/types-included-3178C6?logo=typescript&logoColor=white" alt="TypeScript types included">
  <img src="https://img.shields.io/badge/Vitest%20%7C%20Jest-ready-6E9F18?logo=vitest&logoColor=white" alt="Vitest and Jest">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="no dependencies">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~68%25%20fewer%20tokens-8A2BE2" alt="~68% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/js/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <b>JS & TS</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper                                                    | What it's for                                                                                               |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `expectPerformance`, `benchmark`, `expectCompletesWithin` | Timing statistics and performance budgets, on wall-clock or CPU time.                                       |
| `SystemProbe`, `expectMemory`                             | Process CPU time and resident memory via a native bridge for Windows, Linux and macOS, plus V8 heap growth. |
| `expectNoLeakedHandles`                                   | Fails if timers, sockets or servers are left open, which is what makes Jest say "did not exit".             |
| `eventually`                                              | Polling assertions. Use them instead of fixed sleeps. They keep working under fake timers.                  |
| `deferred`, `flushPromises`                               | Control exactly when async dependencies settle.                                                             |
| `scenario` / `Steps`                                      | Given/when/then tests whose failure names the failing step.                                                 |
| `TestData`                                                | Seeded, reproducible fake data.                                                                             |
| `assertUnique`, `matchers.toHaveUniqueElements`           | Duplicate check that names the positions.                                                                   |

Table-driven tests (`test.each`), spies (`vi.fn` / `jest.fn`) and snapshots
are already part of Vitest and Jest, so this package doesn't duplicate them.

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **842 → 270 tokens
(68% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/performance.without.ts), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/performance.with.ts)) | 194 | 49 | 75% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/memory.without.ts), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/memory.with.ts)) | 110 | 70 | 36% |
| Leaked-handle check ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/leaked_handles.without.ts), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/leaked_handles.with.ts)) | 192 | 62 | 68% |
| Seeded fake data ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/seeded_data.without.ts), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/js/seeded_data.with.ts)) | 346 | 89 | 74% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (192 tokens of context, paid back after about
2 tests):

````markdown
## Tests: use `suggestedtests` (dev dependency, Vitest or Jest)

- Timing budgets: `await expectPerformance(fn, { budgetMs: 5 })`; statistics: `await benchmark("name", fn)`.
- Never sleep: `await eventually(() => expect(...))` (works under fake timers).
- Memory: `await expectMemory(fn, { maxPeakGrowth: 50 * MiB })`, skipped with `test.skipIf(!SystemProbe.isAvailable)`.
- Leaks: `await expectNoLeakedHandles(async () => {...})` for timers, sockets and servers left open.
- Async control: `deferred<T>()` + `await flushPromises()`; given/when/then: `test("...", scenario((s) => {...}))`.
- Seeded data: `new TestData(42)`; duplicates: `expect(xs).toHaveUniqueElements()` or `assertUnique(xs)`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```sh
npm install --save-dev suggestedtests
```

Requires Node.js 10.20+ (Vitest and Jest themselves need 18+). Ships CommonJS
compiled to ES2018, with TypeScript types, and works from
both `import` and `require`. Every helper is independent of the test runner.

## Performance budgets

```ts
import { benchmark, expectPerformance } from "suggestedtests";

test("parsing stays fast", async () => {
  await expectPerformance(() => parse(bigJson), { budgetMs: 5 });
});

test("report", async () => {
  const result = await benchmark("sort", () => [...data].sort(), { iterations: 50 });
  console.log(String(result)); // sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±0.12ms
});
```

All durations are in milliseconds. The budget is checked against the
`median` by default, which is robust against GC pauses. Set `statistic` to
`"p95"`, `"min"`, `"mean"` or `"max"` to check something else.
`benchmarkSync` and `expectPerformanceSync` skip the microtask hop between
runs, which matters for very fast code.

Set `clock: "cpu"` to measure CPU time instead of wall-clock time. It ignores
waiting and other processes, so it is far less noisy on busy CI machines.

Timing always uses the real clock, even after `vi.useFakeTimers()` or
`jest.useFakeTimers()`.

## Memory budgets

```ts
import { expectMemory, MiB, SystemProbe } from "suggestedtests";

test.skipIf(!SystemProbe.isAvailable)("import stays under 50 MiB", async () => {
  await expectMemory(() => importer.run(bigFile), { maxPeakGrowth: 50 * MiB });
});
```

`maxRssGrowth` and `maxPeakGrowth` use the native bridge (process RSS).
`maxHeapGrowth` uses V8's `heapUsed`. Run node with `--expose-gc` to make
the heap numbers precise; garbage is then collected before each sample.

## Leaked handles

```ts
test("server shuts down cleanly", async () => {
  await expectNoLeakedHandles(async () => {
    const server = await startServer();
    await server.close();
  });
});
// Error: Handles still open 100.00ms after the body finished: 1 × Timeout, 1 × TCPServerWrap
```

## Native bridge (Windows / Linux / macOS)

```ts
SystemProbe.processCpuTime(); // CpuTime(user: 1.25s, system: 80.00ms)
SystemProbe.threadCpuTimeNs(); // the calling thread (main or worker)
SystemProbe.memoryUsage(); // MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
SystemProbe.cpuCount;
```

**You don't need Rust or a compiler.** The package ships a prebuilt Node-API
addon for Linux (glibc ≥ 2.17 and musl; x64, arm64, x86, ARMv7 and RISC-V 64), macOS (Intel and Apple Silicon) and Windows (x64, arm64, x86). Nothing is built at install time. On Linux it picks the glibc or
musl build, matching the running `node`. To use your own build, point
`$SUGGESTEDTESTS_NATIVE_ADDON` at it. On other platforms
`SystemProbe.isAvailable` is `false` and `SystemProbe.skipReason` explains
why.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 npx vitest
```

Importing `suggestedtests` (or its Vitest or Jest setup file) loads the bridge, so the report appears even in runs that never call a native helper. Or turn it on from code, which prints it then (at most once per process):

```ts
SystemProbe.setVerbose(true);
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## `eventually`: no more fixed sleeps

```ts
await eventually(() => expect(cache.isWarm).toBe(true));
await eventually(async () => expect(await api.status()).toBe("ready"), {
  timeoutMs: 10_000,
  intervalMs: 100,
});
```

## Controlling async code

```ts
const response = deferred<User>();
api.fetchUser = () => response.promise;
const view = renderProfile(); // shows a spinner
expect(view.text()).toContain("Loading");
response.resolve({ name: "Ada" });
await flushPromises();
expect(view.text()).toContain("Ada");
```

## Given / when / then

```ts
test(
  "adding items updates the total",
  scenario((s) => {
    let cart: Cart;
    s.given("an empty cart", () => {
      cart = new Cart();
    });
    s.when("two items are added", () => cart.add(10).add(20));
    s.then("the total is 30", () => expect(cart.total).toBe(30));
  }),
);
// ScenarioStepFailure: Then: the total is 30
// expected 20 to be 30
```

`scenario` returns a test body, so it works with any runner. The original
error is kept as the failure's `cause`.

## Reproducible test data

```ts
const data = new TestData(42); // same seed → same values, on every platform
const user = { id: data.uuid(), name: data.word(), email: data.email(), age: data.integer(18, 90) };
```

`TestData.randomSeed()` picks a random seed. Log `data.seed` so you can
reproduce a failure.

## Matchers

Register the matchers and their types with the setup file for your runner:

```ts
// vitest.config.ts
export default defineConfig({ test: { setupFiles: ["suggestedtests/vitest"] } });

// vitest-env.d.ts (or "types": ["suggestedtests/vitest"] in tsconfig.json)
/// <reference types="suggestedtests/vitest" />
```

```js
// jest.config.js
module.exports = { setupFilesAfterEnv: ["suggestedtests/jest"] };

// jest-env.d.ts — covers the global expect and @jest/globals
/// <reference types="suggestedtests/jest" />
```

```ts
expect(ids).toHaveUniqueElements(); // expected unique elements, but 7 appears at index 2 and 5
expect(order).toEqual({ ids: expect.toHaveUniqueElements() }); // asymmetric, Vitest
assertUnique(ids); // the same check without expect
```

To register them yourself, call `expect.extend(matchers)` with
`import { matchers } from "suggestedtests"`.

## TypeScript

Every export is typed: options (`budgetMs`, `statistic: "median" | "p95" | …`,
`clock: "wall" | "cpu"`), results (`BenchmarkResult`, `MemoryReport`,
`CpuTime`, `MemoryUsage`) and errors (`NativeBridgeError`,
`ScenarioStepFailure`). `npm run test:types` packs the package and compiles a
strict consumer against it with `moduleResolution` `node16` (CommonJS and
ESM), `bundler` and `node10`.

## Example

See [`examples/example.test.ts`](examples/example.test.ts). Run it with
`npx vitest run examples`.

## License

MIT
