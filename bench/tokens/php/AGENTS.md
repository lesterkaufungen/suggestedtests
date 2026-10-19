## Tests: use `suggestedtests` (`use SuggestedTests\PHPUnit\SuggestedTests;` in the test class)

- Timing budgets: `$this->assertPerformance(fn () => ..., budgetMs: 5)`; statistics: `Benchmark::run('name', fn () => ...)`.
- Never `sleep()`: `$this->assertEventually(fn () => $this->assert...(...))`.
- Memory: `$this->assertMemory(fn () => ..., maxHeapGrowth: 1 * Memory::MiB)` or `maxPeakGrowth:` for RSS.
- Isolation: `Sandbox::withEnv([...], fn)`, `Sandbox::withIni([...], fn)`, `Sandbox::captureOutput(fn)`, `$this->temporaryDirectory()`.
- Given/when/then: `$this->scenario(function (Steps $s) {...})`; spies: `new Spy()` + `assertSpyCalledWith`; snapshots: `assertMatchesSnapshot`.
- Seeded data: `$this->testData()`; duplicates: `assertUniqueElements`.
