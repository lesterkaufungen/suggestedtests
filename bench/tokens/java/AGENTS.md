## Tests: use `suggestedtests` (test dependency, JUnit 5/6 or the JUnit 4 rule)

- Timing budgets: `Benchmark.of("name", () -> ...).assertWithin(Duration.ofMillis(5))`.
- Never `Thread.sleep`: `Eventually.eventually(() -> assertTrue(...))`; futures: `assertCompletesWithin(timeout, future)`.
- Memory: `@MemoryBudget(maxPeakGrowthBytes = 50 * Memory.MiB)` with `@RequiresNativeBridge`, or `Memory.budget().maxHeapGrowth(...).check(...)`.
- Concurrency and leaks: `Concurrency.race(threads, body)`, `Leaks.assertGarbageCollected(() -> obj)`, `Leaks.assertNoLeakedThreads(body)`.
- Given/when/then: `Scenario.given(...).when(...).then(...)`; spies: `Spy.consumer()` + `assertCalledWith`.
- Seeded data: `@SuggestedTests` + a `TestData data` parameter; duplicates: `assertUnique(items)`.
