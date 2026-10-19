<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for Java</h1>

<p align="center">
  JUnit 5 helpers that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://central.sonatype.com/artifact/io.github.lesterkaufungen/suggestedtests"><img src="https://img.shields.io/maven-central/v/io.github.lesterkaufungen/suggestedtests?logo=apachemaven&color=C71A36&label=Maven%20Central" alt="Maven Central"></a>
  <img src="https://img.shields.io/badge/Java-8%2B-ED8B00?logo=openjdk&logoColor=white" alt="Java 8+">
  <img src="https://img.shields.io/badge/Android-API%2021%2B-3DDC84?logo=android&logoColor=white" alt="Android API 21+">
  <img src="https://img.shields.io/badge/JUnit-4%20%7C%205%20%7C%206-25A162?logo=junit5&logoColor=white" alt="JUnit 4, 5 and 6">
  <img src="https://img.shields.io/badge/TestNG-7-E87722" alt="TestNG">
  <img src="https://img.shields.io/badge/Kotlin-friendly-7F52FF?logo=kotlin&logoColor=white" alt="works from Kotlin">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~61%25%20fewer%20tokens-8A2BE2" alt="~61% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/java/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/php">PHP</a> · <b>Java</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper | What it's for |
| --- | --- |
| `Benchmark` | Timing statistics and performance budgets, on wall-clock or CPU time. |
| `Memory`, `@MemoryBudget` | Java heap and process RSS budgets. RSS comes from a native bridge (JNI) for Windows, Linux and macOS. |
| `SystemProbe` | Process CPU time, thread CPU time, current and peak RSS, CPU count. |
| `Concurrency.race` | Releases N threads at once to expose races. Reports stuck threads with their stacks. |
| `Leaks` | `assertGarbageCollected` (no listener or cache leaks) and `assertNoLeakedThreads`. |
| `Eventually` | `eventually(...)` polling instead of `Thread.sleep`, plus `assertCompletesWithin(future)`. |
| `Scenario` | Given/when/then tests whose failure names the failing step. |
| `Spy` + `assertCalled…` | Spies for any functional interface, with no mocking framework. |
| `TestData`, `@SuggestedTests`, `@Seed` | Seeded, reproducible fake data, injected per test. A failure reports the seed. |
| `assertUnique`, `@RequiresNativeBridge` | Duplicate check that names positions; skip tests where the bridge is unavailable. |

For timeouts and table-driven tests, use JUnit's `assertTimeout` and
`@ParameterizedTest`. They already do the job well, so this library doesn't
duplicate them.

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **792 → 309 tokens
(61% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/performance.without.java), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/performance.with.java)) | 211 | 66 | 69% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/eventually.without.java), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/eventually.with.java)) | 125 | 64 | 49% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/memory.without.java), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/memory.with.java)) | 231 | 103 | 55% |
| GC-leak check ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/gc_leaks.without.java), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/java/gc_leaks.with.java)) | 225 | 76 | 66% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (215 tokens of context, paid back after about
2 tests):

````markdown
## Tests: use `suggestedtests` (test dependency, JUnit 5/6 or the JUnit 4 rule)

- Timing budgets: `Benchmark.of("name", () -> ...).assertWithin(Duration.ofMillis(5))`.
- Never `Thread.sleep`: `Eventually.eventually(() -> assertTrue(...))`; futures: `assertCompletesWithin(timeout, future)`.
- Memory: `@MemoryBudget(maxPeakGrowthBytes = 50 * Memory.MiB)` with `@RequiresNativeBridge`, or `Memory.budget().maxHeapGrowth(...).check(...)`.
- Concurrency and leaks: `Concurrency.race(threads, body)`, `Leaks.assertGarbageCollected(() -> obj)`, `Leaks.assertNoLeakedThreads(body)`.
- Given/when/then: `Scenario.given(...).when(...).then(...)`; spies: `Spy.consumer()` + `assertCalledWith`.
- Seeded data: `@SuggestedTests` + a `TestData data` parameter; duplicates: `assertUnique(items)`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```xml
<dependency>
  <groupId>io.github.lesterkaufungen</groupId>
  <artifactId>suggestedtests</artifactId>
  <version>0.1.1</version>
  <scope>test</scope>
</dependency>
```

```kotlin
testImplementation("io.github.lesterkaufungen:suggestedtests:0.1.1")
```

Requires Java 8+ and works with JUnit 5 and 6, JUnit 4 (`SuggestedTestsRule`),
TestNG, Gradle and Kotlin. It has no dependencies of its own.

### Kotlin, Gradle and Android

```kotlin
testImplementation("io.github.lesterkaufungen:suggestedtests:0.1.1")               // JVM / Android local tests
androidTestImplementation("io.github.lesterkaufungen:suggestedtests-android:0.1.1") // on devices (AAR)

Scenario.given("an empty cart") { Cart() }
    .`when`("two items are added") { it.add(10).add(20) }
    .then("the total is 30") { assertEquals(30, it.total) }
Benchmark.of("parse") { parser.parse(json) }.assertWithin(Duration.ofMillis(5))
```

Android projects run JUnit 4 by default, so use the rule there; it honours the
same annotations as the JUnit 5 extension:

```java
@Rule public final SuggestedTestsRule st = new SuggestedTestsRule();

@Test
@RequiresNativeBridge
@MemoryBudget(maxPeakGrowthBytes = 64 * Memory.MiB)
public void importStaysSmall() { importer.run(st.testData().word()); }
```

### TestNG, Spock, Kotest

Every helper fails with a plain `AssertionError` and needs no JUnit class, so
they all work in TestNG (tested with 7.5, on Java 8 and 21, with no JUnit on the
classpath), and in Spock and Kotest. The JUnit annotations (`@SuggestedTests`,
`@MemoryBudget`, `@Seed`) don't apply there; use the same helpers directly:

```java
public class ImporterTest { // TestNG
  @Test public void importStaysSmall() {
    Memory.budget().maxPeakGrowth(64 * Memory.MiB).check(() -> importer.run(new TestData(42).word()));
  }
}
```

TestNG runs load the native bridge when they start (a TestNG listener, found
automatically), as JUnit Platform runs do, which is where Spock and Kotest run.

The AAR carries the bridge for arm64-v8a, armeabi-v7a, x86_64 and x86 (API
21+, 16 KB pages). The Java API itself uses `java.time` and
`java.util.function`, so on devices below API 26 enable
[core library desugaring](https://developer.android.com/studio/write/java8-support#library-desugaring).

## Performance budgets

```java
@Test
void parsingStaysFast() {
  Benchmark.of("parse", () -> parser.parse(json)).assertWithin(Duration.ofMillis(5));
}

@Test
void report() {
  BenchmarkResult r = Benchmark.of("sort", () -> sort(data)).iterations(50).warmup(10).run();
  System.out.println(r); // sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±120µs
}
```

The budget is checked against the median by default, which is robust against
GC pauses. Use `.statistic(Statistic.P95)` (or `MIN`, `MEAN`, `MAX`) to check
something else. Raise `.warmup(n)` so the JIT has compiled the code before
timing starts.

`.clock(Clock.CPU)` measures the CPU time of the test thread. It ignores
waiting, GC and JIT threads, and other processes, so it is far less noisy on
busy CI machines.

## Memory budgets

```java
@Test
@MemoryBudget(maxPeakGrowthBytes = 64 * Memory.MiB)
void importStaysSmall() {
  importer.run(bigFile);
}

@Test
void cacheIsBounded() {
  Memory.budget().maxHeapGrowth(8 * Memory.MiB).check(() -> fill(cache, 100_000));
}
```

RSS budgets (`maxRssGrowth`, `maxPeakGrowth`) see everything the process
holds: heap, direct buffers, native libraries. Heap budgets ask the JVM to
collect garbage before each sample. `System.gc()` is only a hint, so leave
room for noise.

## Native bridge (Windows / Linux / macOS)

```java
SystemProbe.processCpuTime();   // CpuTime(user: 1.25s, system: 80.00ms)
SystemProbe.threadCpuTimeNs();  // the calling thread
SystemProbe.memoryUsage();      // MemoryUsage(current: 140.1 MiB, peak: 152.3 MiB)
SystemProbe.cpuCount();
```

**You don't need Rust or a compiler.** The jar contains the bridge prebuilt
for Linux (glibc ≥ 2.17 and musl; x64, arm64, x86, ARMv7 and RISC-V 64), macOS (Intel and Apple Silicon) and Windows (x64, arm64, x86); a 32-bit JVM gets the 32-bit build. It is extracted to a temporary file and loaded through JNI. To use
your own build, pass `-Dsuggestedtests.native.lib=<path>` (or set
`$SUGGESTEDTESTS_NATIVE_LIB`). `@RequiresNativeBridge` skips a test or
class, with the reason, where the bridge is unavailable.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 ./mvnw test   # or -Dsuggestedtests.verbose=true
```

Every JUnit Platform or TestNG run (Maven, Gradle, IDEs) loads the bridge when it starts, as do `SuggestedTestsRule` and `@SuggestedTests`, so the report appears even in runs that never call a native helper. Or turn it on from code, which prints it then (at most once per process):

```java
SystemProbe.setVerbose(true);
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## Concurrency and leaks

```java
@Test
void counterIsThreadSafe() {
  Counter counter = new Counter();
  Concurrency.race(8, thread -> { for (int i = 0; i < 10_000; i++) counter.increment(); });
  assertEquals(80_000, counter.get());
}

@Test
void unregisteredViewsAreReleased() {
  Leaks.assertGarbageCollected(() -> {
    View view = new View();
    bus.register(view);
    bus.unregister(view);
    return view;
  });
}

@Test
void poolShutsDown() {
  Leaks.assertNoLeakedThreads(() -> { try (var pool = new WorkerPool(4)) { pool.submit(job); } });
}
```

All threads in `race` start at the same moment, which maximises contention.
If they don't finish within 10 seconds, the failure prints each stuck
thread's stack, which usually points at the deadlock.

## `eventually`: no more fixed sleeps

```java
import static io.github.lesterkaufungen.suggestedtests.Eventually.*;

eventually(() -> assertTrue(cache.isWarm()));
Order order = eventually(Duration.ofSeconds(10), Duration.ofMillis(100), () -> orders.find(id).orElseThrow());
User user = assertCompletesWithin(Duration.ofSeconds(1), client.fetchUser(42));
```

## Given / when / then

```java
Scenario.given("an empty cart", Cart::new)
    .when("two items are added", cart -> cart.add(10).add(20))
    .then("the total is 30", cart -> assertEquals(30, cart.total()));
Scenario.givenThat("the server is up", server::start); // a setup step without a value
// ScenarioStepFailure: Then: the total is 30
// org.opentest4j.AssertionFailedError: expected: <30> but was: <20>
// Passed steps:
//   ✓ Given: an empty cart
//   ✓ When: two items are added
```

The value produced by `given` is passed to every later step, so you don't need
fields or holder arrays.

## Spies

```java
Spy<Consumer<String>> onChange = Spy.consumer();
field.onChange(onChange.get());
field.type("hi");

assertCalledTimes(onChange, 1);
assertCalledWith(onChange, "hi");
assertCalledWith(onChange, argThat("non-empty", (String s) -> !s.isEmpty()));

Spy<Function<String, Integer>> parse = Spy.function(Integer::parseInt); // delegates
Spy<PriceListener> listener = Spy.of(PriceListener.class, null);       // any functional interface
```

## Reproducible test data

```java
@SuggestedTests
class SignupTest {
  @Test
  void acceptsAnyValidEmail(TestData data) {
    assertTrue(signup.accepts(data.email()));
  }
}
```

Each test gets a fresh seed. When a test fails, the seed is attached to the
failure (`TestData seed was 1804289383; reproduce with
-Dsuggestedtests.seed=1804289383`). `@Seed(42)` fixes it for a test or a
class. `new TestData(42)` works anywhere. It has its own xoshiro256**
generator, so a seed produces the same values on every JVM and on Android, and
the same values as the Go package.

## Example

See [`ExampleTest.java`](src/test/java/io/github/lesterkaufungen/suggestedtests/examples/ExampleTest.java).
Run it with `./mvnw test -Dtest=ExampleTest`.

## License

MIT
