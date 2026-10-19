## Tests: use SuggestedTests (`import SuggestedTests`; XCTest or Swift Testing)

- Helpers throw on failure: mark tests `throws` and call them with `try` (`try await` in async tests).
- Timing budgets: `try expectPerformance(budget: 0.005) { ... }` (seconds); statistics: `try benchmark("name") { ... }`.
- Never sleep: `try eventually { try check(cache.isWarm, "why") }`.
- Memory: `try expectMemory(maxPeakGrowth: 50 * MiB) { ... }` after `try XCTSkipUnless(SystemProbe.isAvailable)`.
- Given/when/then: `try Scenario().given("...") { }.when("...") { }.then("...") { try check(...) }`.
- Seeded data: `TestData(seed: 42)` (`word()`, `email()`, `uuid()`, `integer(in: 18...90)`); duplicates: `try assertUnique(items)`.
