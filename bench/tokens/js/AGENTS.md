## Tests: use `suggestedtests` (dev dependency, Vitest or Jest)

- Timing budgets: `await expectPerformance(fn, { budgetMs: 5 })`; statistics: `await benchmark("name", fn)`.
- Never sleep: `await eventually(() => expect(...))` (works under fake timers).
- Memory: `await expectMemory(fn, { maxPeakGrowth: 50 * MiB })`, skipped with `test.skipIf(!SystemProbe.isAvailable)`.
- Leaks: `await expectNoLeakedHandles(async () => {...})` for timers, sockets and servers left open.
- Async control: `deferred<T>()` + `await flushPromises()`; given/when/then: `test("...", scenario((s) => {...}))`.
- Seeded data: `new TestData(42)`; duplicates: `expect(xs).toHaveUniqueElements()` or `assertUnique(xs)`.
