## Tests: use suggestedtests (`st "github.com/lesterkaufungen/suggestedtests/packages/go"`)

- Timing budgets: `st.ExpectPerformance(t, 5*time.Millisecond, fn)`.
- Never `time.Sleep`: `st.Eventually(t, func() error {...})`.
- Memory: `st.ExpectMemory(t, fn, st.MaxPeakGrowth(50*st.MiB))` after `st.RequireNativeBridge(t)`; allocations: `st.MaxAllocs(0)`.
- Leaks and races: `st.NoGoroutineLeaks(t)` as the first line; `st.Race(t, n, func(i int) error {...})`.
- Given/when/then: `st.NewScenario(t).Given(...).When(...).Then(...)`; golden files: `st.Golden(t, "name", got)`.
- Seeded data: `d := st.Data(t)`; duplicates: `st.AssertUnique(t, items)`.
