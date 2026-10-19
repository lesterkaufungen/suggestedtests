## Tests: use `suggestedtests` (dev dependency)

- Table-driven: `testCases<In, Out>('name', [TestCase(input, expected)], (input, expected) {...})`; widgets: `testWidgetsCases`.
- Timing budgets: `await expectPerformance(fn, budget: const Duration(milliseconds: 5))`; statistics: `benchmark` / `benchmarkSync`.
- Never sleep: `await eventually(() => expect(...))`; in widget tests `tester.pumpUntilFound(finder)` / `pumpUntilGone(finder)`.
- Memory: `await expectMemory(fn, maxPeakGrowthBytes: 50 * 1024 * 1024)` with `skip: SystemProbe.skipReason`.
- Given/when/then: `scenario('name', (s) { s.given(...); s.when(...); s.then(...); })`, `scenarioWidgets`.
- Seeded data: `TestData(42)`; spies: `Spy1<A, R>(fn)` + `wasCalledWith([...])`; widgets: `tester.pumpApp(widget)`, `tapAndSettle`, `enterTextAndSettle`.
