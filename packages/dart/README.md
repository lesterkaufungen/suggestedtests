<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for Flutter & Dart</h1>

<p align="center">
  Write Flutter and Dart tests faster, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://pub.dev/packages/suggestedtests"><img src="https://img.shields.io/pub/v/suggestedtests?logo=dart&logoColor=white&label=pub.dev&color=0175C2" alt="pub.dev"></a>
  <img src="https://img.shields.io/badge/Flutter-3.38.4%2B-02569B?logo=flutter&logoColor=white" alt="Flutter 3.38.4+">
  <img src="https://img.shields.io/badge/Dart-3.10%2B-0175C2?logo=dart&logoColor=white" alt="Dart 3.10+">
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20web%20%7C%20desktop-02569B" alt="all Flutter platforms">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~52%25%20fewer%20tokens-8A2BE2" alt="~52% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/dart/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <b>Flutter & Dart</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

`suggestedtests` adds a few small helpers on top of `flutter_test`. They remove
the boilerplate you write over and over, and they let your tests fail when code
gets slower than a budget you set.

| Helper | What it's for |
| --- | --- |
| `testCases`, `testWidgetsCases` | Table-driven tests. Each row becomes its own named test. |
| `scenario`, `scenarioWidgets` | Given/when/then tests whose failure report names the failing step. |
| `benchmark`, `expectPerformance`, `expectCompletesWithin` | Timing statistics and performance budgets, on wall-clock or CPU time. |
| `SystemProbe`, `expectMemory` | Process CPU time and memory via a native bridge for Windows, Linux and macOS. |
| `eventually` | Polling assertions. Use them instead of `Future.delayed` sleeps. |
| `Spy0`, `Spy1`, `Spy2` + `wasCalled…` matchers | Callback spies with no mocking framework and no code generation. |
| `TestData` | Seeded, reproducible fake data (ints, strings, emails, UUIDs, dates). |
| `hasUniqueElements` | Collection matcher that names the duplicate. |
| `tester.pumpApp`, `tapAndSettle`, `enterTextAndSettle`, `pumpUntilFound`, `pumpUntilGone` | `WidgetTester` shortcuts. |

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **540 → 261 tokens
(52% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/performance.without.dart), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/performance.with.dart)) | 198 | 64 | 68% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/eventually.without.dart), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/eventually.with.dart)) | 102 | 52 | 49% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/memory.without.dart), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/memory.with.dart)) | 117 | 82 | 30% |
| Wait for a widget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/pump_until_found.without.dart), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/dart/pump_until_found.with.dart)) | 123 | 63 | 49% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (236 tokens of context, paid back after about
4 tests):

````markdown
## Tests: use `suggestedtests` (dev dependency)

- Table-driven: `testCases<In, Out>('name', [TestCase(input, expected)], (input, expected) {...})`; widgets: `testWidgetsCases`.
- Timing budgets: `await expectPerformance(fn, budget: const Duration(milliseconds: 5))`; statistics: `benchmark` / `benchmarkSync`.
- Never sleep: `await eventually(() => expect(...))`; in widget tests `tester.pumpUntilFound(finder)` / `pumpUntilGone(finder)`.
- Memory: `await expectMemory(fn, maxPeakGrowthBytes: 50 * 1024 * 1024)` with `skip: SystemProbe.skipReason`.
- Given/when/then: `scenario('name', (s) { s.given(...); s.when(...); s.then(...); })`, `scenarioWidgets`.
- Seeded data: `TestData(42)`; spies: `Spy1<A, R>(fn)` + `wasCalledWith([...])`; widgets: `tester.pumpApp(widget)`, `tapAndSettle`, `enterTextAndSettle`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```sh
flutter pub add --dev suggestedtests
```

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';
```

Requires Flutter 3.38.4+ (Dart 3.10, the first with stable build hooks).

The package is for tests only. It has no platform code, so it works the same
for Android, iOS, web and desktop apps, and with plain `flutter test`.

## Table-driven tests

```dart
testCases<String, int>('String.length', const [
  TestCase('', 0),
  TestCase('abc', 3),
  TestCase('héllo', 5, name: 'non-ascii'),
  TestCase('x', 99, skip: 'known bug #12'),
], (input, expected) {
  expect(input.length, expected);
});
```

Each row is registered as a separate test (`[0] '' -> 0`, `[2] non-ascii`, …).
A failing row doesn't hide the others, and you can rerun a single row by name.
For widget tests, `testWidgetsCases` passes the `WidgetTester` as well.

## Given / when / then

```dart
scenario('adding items updates the total', (s) {
  late Cart cart;
  s.given('an empty cart', () => cart = Cart());
  s.when('two items are added', () => cart..add(10)..add(20));
  s.then('the total is 30', () => expect(cart.total, 30));
});

scenarioWidgets('tapping + increments the counter', (tester, s) {
  s.given('the counter page', () => tester.pumpApp(const CounterPage()));
  s.when('+ is tapped', () => tester.tapAndSettle(find.byIcon(Icons.add)));
  s.then('it shows 1', () => expect(find.text('1'), findsOneWidget));
});
```

When a step fails, the error starts with the step, for example
`Then: the total is 30`, followed by the original expectation failure.

## Performance budgets

```dart
test('parsing stays fast', () async {
  final result = await expectPerformance(
    () => parse(bigJson),
    budget: const Duration(milliseconds: 5),
    statistic: Statistic.median, // min | mean | median | p95 | max
    iterations: 30,
    warmup: 5,
  );
  print(result); // parse: n=30 min=3.10ms median=3.42ms mean=3.51ms p95=4.02ms max=4.30ms ±0.21ms
});

test('loads within a second', () async {
  final user = await expectCompletesWithin(repo.load(), const Duration(seconds: 1));
});
```

`benchmark` (async) and `benchmarkSync` return a `BenchmarkResult` with
`min`, `max`, `mean`, `median`, `p95`, `stdDev` and `percentile(p)`. Use them
to track numbers without failing the test.

> **Tip:** the median is the default because it is robust against GC pauses
> and noisy CI machines. Use `Statistic.p95` when tail latency matters.

### CPU time instead of wall-clock time

On a shared CI machine, wall-clock timings change with whatever else is
running. Pass `clock: BenchmarkClock.cpu` to measure the CPU time your code
actually used:

```dart
final r = benchmarkSync('sort', () => list.sort(), clock: BenchmarkClock.cpu);
await expectPerformance(() => parse(json),
    budget: const Duration(milliseconds: 5), clock: BenchmarkClock.cpu);
```

`benchmarkSync` measures the calling thread. `benchmark` (async) measures the
whole process, because an isolate can resume on another OS thread after an
`await`. The CPU clock uses the [native bridge](#native-bridge-windows--linux--macos).

## Native bridge (Windows / Linux / macOS)

`SystemProbe` reads process metrics through a small Rust library with one C
interface on every OS:

| Call | Windows | Linux | macOS |
| --- | --- | --- | --- |
| `processCpuTime()` | `GetProcessTimes` | `getrusage` | `getrusage` |
| `threadCpuTime()` | `GetThreadTimes` | `clock_gettime(CLOCK_THREAD_CPUTIME_ID)` | same |
| `memoryUsage()` | `K32GetProcessMemoryInfo` | `/proc/self/statm` + `getrusage` | `proc_pidinfo` + `getrusage` |
| `cpuCount` | Rust `available_parallelism` | same | same |

```dart
final before = SystemProbe.processCpuTime();
doWork();
print(SystemProbe.processCpuTime() - before); // CpuTime(user: ..., system: ...)
print(SystemProbe.memoryUsage());             // MemoryUsage(current: 182.4 MiB, peak: 190.1 MiB)

test('import does not leak', skip: SystemProbe.skipReason, () async {
  await expectMemory(
    () => importer.run(bigFile),
    maxRssGrowthBytes: 20 * 1024 * 1024,
  );
});
```

**You don't need Rust.** The package ships precompiled libraries, and a
[build hook](hook/build.dart) bundles the right one when your tests run:

| Folder in `native/prebuilt/` | Runs on |
| --- | --- |
| `linux-x64`, `linux-arm64`, `linux-x86`, `linux-arm`, `linux-riscv64` | any glibc distro with glibc ≥ 2.17 (≥ 2.27 on RISC-V): Ubuntu, Debian, Fedora, RHEL/CentOS 7+, Raspberry Pi OS, … |
| the same with `-musl` | musl distros (Alpine, …) |
| `macos-x64`, `macos-arm64` | macOS 10.13+ (Intel) / 11+ (Apple Silicon) |
| `windows-x64`, `windows-arm64`, `windows-x86` | Windows 10+ (static CRT, no VC++ redistributable needed) |
| `android-arm64-v8a`, `-armeabi-v7a`, `-x86_64`, `-x86` | Android 5.0+ (API 21), for integration tests on a device |

On Linux, the hook reads the C library the running Dart VM uses (glibc or
musl) and picks the matching build. It compiles with `cargo` **only** when no
precompiled library exists for the platform. If neither is possible, the rest
of the package works as usual, `SystemProbe.isAvailable` is `false`, and
`skipReason` explains why.

RSS is a coarse, process-wide signal, because the Dart GC keeps freed memory
for reuse. Use `expectMemory` to catch leaks and blow-ups measured in
megabytes, not to count objects.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 flutter test
```

The first call into the package, usually registering tests with `testCases` or `scenario`, loads the bridge, so the report appears even in runs that never call a native helper. Or turn it on from code, which prints it then (at most once per process):

```dart
SystemProbe.setVerbose(true);
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## `eventually`: no more fixed sleeps

```dart
await eventually(() => expect(cache.isWarm, isTrue));
await eventually(
  () async => expect(await api.status(), 'ready'),
  timeout: const Duration(seconds: 10),
  interval: const Duration(milliseconds: 100),
);
```

The test continues as soon as the condition holds. A fixed delay always waits
for the worst case, so `eventually` makes slow suites faster and flaky suites
stable. It uses real timers. Inside `testWidgets`, use `tester.pumpUntilFound`
instead.

## Spies

```dart
final onChanged = Spy1<String, void>((_) {});
await tester.pumpApp(TextField(onChanged: onChanged.call));
await tester.enterTextAndSettle(find.byType(TextField), 'hi');

expect(onChanged, wasCalledTimes(1));
expect(onChanged, wasCalledWith(['hi']));
expect(onChanged, wasCalledWith([startsWith('h')])); // matchers work too
expect(onChanged.lastCall, ['hi']);
```

`Spy0`, `Spy1` and `Spy2` cover callbacks with 0, 1 and 2 arguments. Each spy
delegates to the implementation you pass, so it can return values too:
`Spy1<int, int>((x) => x * 2)`.

## Reproducible test data

```dart
final data = TestData(42); // same seed → same values, every run
final user = User(
  id: data.uuid(),
  name: data.word(),
  email: data.email(),          // e.g. delta.qwxyz@example.com
  age: data.integer(18, 90),    // inclusive
  joined: data.date(from: DateTime.utc(2020)),
);
final users = data.listOf(100, (d) => User.random(d));
```

`TestData.randomSeed()` picks a random seed. Log `data.seed` so you can
reproduce a failure.

## Matchers

```dart
expect(ids, hasUniqueElements); // fails with: contains duplicate <7>
```

For sorting and counting, use the matchers `flutter_test` already includes:
`containsOnce`, and from Flutter 3.41 `isSorted`, `isSortedBy` and
`isSortedUsing`.

## WidgetTester shortcuts

```dart
await tester.pumpApp(const MyWidget());                     // MaterialApp + Scaffold
await tester.pumpApp(const MyPage(), wrapInScaffold: false);
await tester.pumpApp(const MyWidget(), surfaceSize: const Size(320, 640)); // auto-reset
await tester.tapAndSettle(find.text('Save'));
await tester.enterTextAndSettle(find.byType(TextField), 'hello');
await tester.pumpUntilFound(find.text('Loaded'));            // works with spinners
await tester.pumpUntilGone(find.byType(CircularProgressIndicator));
```

`pumpAndSettle` times out on endless animations such as
`CircularProgressIndicator`. `pumpUntilFound` and `pumpUntilGone` don't, because
they stop as soon as the condition is met.

## Example

See [`example/example.dart`](example/example.dart). Run it with
`flutter test example/example.dart`.

## Other languages

The same helpers, and the same native bridge, exist for
[Python](https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python) (pytest),
[JavaScript/TypeScript](https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js) (Vitest, Jest),
[PHP](https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php) (PHPUnit),
[Java](https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java) (JUnit 5) and
[Go](https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go) (`testing`).

## License

MIT
