## Tests: use `suggestedtests` (pytest plugin, loads automatically)

- Timing budgets: `expect_performance(fn, budget=0.005)` (seconds); statistics: `benchmark("name", fn)`.
- Never `time.sleep`: `eventually(fn)` retries until `fn` stops raising `AssertionError`.
- Memory: `with expect_memory(max_peak_growth=50 * MiB):` plus `@pytest.mark.requires_native_bridge`; Python heap: `with expect_allocations(max_net=64 * KiB):`.
- Leaks: `with no_leaked_threads():`.
- Given/when/then: the `steps` fixture (`with steps.given("..."):`); seeded data: the `test_data` fixture.
- Duplicates: `assert_unique(items)`. For parametrize and mocks, use pytest and `unittest.mock`.
