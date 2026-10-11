<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/assets/logo.png" alt="suggestedtests logo" width="160">
</p>

<h1 align="center">suggestedtests</h1>

<p align="center">
  Write Flutter and Dart tests faster, and keep your code fast.
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

## Install

```sh
flutter pub add --dev suggestedtests
```

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';
```

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
| `linux-x64`, `linux-arm64` | any glibc distro with glibc ≥ 2.17 (Ubuntu, Debian, Fedora, RHEL/CentOS 7+, …) |
| `linux-x64-musl`, `linux-arm64-musl` | musl distros (Alpine, …) |
| `macos-x64`, `macos-arm64` | macOS 10.13+ (Intel) / 11+ (Apple Silicon) |
| `windows-x64`, `windows-arm64` | Windows 10+ (static CRT, no VC++ redistributable needed) |

On Linux, the hook reads the C library the running Dart VM uses (glibc or
musl) and picks the matching build. It compiles with `cargo` **only** when no
precompiled library exists for the platform. If neither is possible, the rest
of the package works as usual, `SystemProbe.isAvailable` is `false`, and
`skipReason` explains why.

RSS is a coarse, process-wide signal, because the Dart GC keeps freed memory
for reuse. Use `expectMemory` to catch leaks and blow-ups measured in
megabytes, not to count objects.

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
`isSorted`, `isSortedBy`, `isSortedUsing` and `containsOnce`.

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

## License

MIT
