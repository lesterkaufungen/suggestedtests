<p align="center">
  <img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/packages/dart/assets/logo.png" alt="suggestedtests logo" width="140">
</p>

<h1 align="center">suggestedtests for PHP</h1>

<p align="center">
  PHPUnit helpers that make tests faster to write, and keep your code fast.
</p>

<p align="center">
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://raw.githubusercontent.com/lesterkaufungen/suggestedtests/main/bench/tokens/banner.png" alt="Tokens an AI coding agent spends per test, hand-written vs with suggestedtests, projected to larger test suites (estimate)" width="900"></a>
</p>

<p align="center">
  <a href="https://packagist.org/packages/lesterkaufungen/suggestedtests"><img src="https://img.shields.io/packagist/v/lesterkaufungen/suggestedtests?logo=packagist&logoColor=white&color=F28D1A" alt="Packagist"></a>
  <img src="https://img.shields.io/badge/PHP-7.4%2B-777BB4?logo=php&logoColor=white" alt="PHP 7.4+">
  <img src="https://img.shields.io/badge/PHPUnit-9.6%20to%2012-3C9CD7" alt="PHPUnit 9.6 to 12">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="no dependencies">
  <!-- tokens:badge -->
<!-- prettier-ignore-start -->
<a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md"><img src="https://img.shields.io/badge/AI%20agents-~56%25%20fewer%20tokens-8A2BE2" alt="~56% fewer tokens for AI agents (estimate)"></a>
<!-- prettier-ignore-end -->
<!-- /tokens:badge -->
  <a href="https://github.com/lesterkaufungen/suggestedtests/blob/main/packages/php/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <sub>The same helpers in <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/dart">Flutter & Dart</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/python">Python</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/js">JS & TS</a> · <b>PHP</b> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/java">Java</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/go">Go</a> · <a href="https://github.com/lesterkaufungen/suggestedtests/tree/main/packages/swift">Swift</a> · <a href="https://github.com/lesterkaufungen/suggestedtests">one repo, one native bridge</a></sub>
</p>

---

| Helper | What it's for |
| --- | --- |
| `assertPerformance`, `Benchmark` | Timing statistics and performance budgets, on wall-clock or CPU time. |
| `assertMemory`, `Memory` | PHP heap budgets, and process RSS via a native bridge (ext-ffi) for Windows, Linux and macOS. |
| `SystemProbe` | Process CPU time, thread CPU time, current and peak RSS, CPU count. |
| `assertEventually`, `Eventually` | Polling assertions. Use them instead of `sleep()`. |
| `scenario`, `Steps` | Given/when/then tests whose failure names the failing step. |
| `Spy` + `assertSpyCalled…` | Spies for closures and callables. Arguments can be PHPUnit constraints. |
| `assertMatchesSnapshot` | Snapshot files next to the test, updated with one environment variable. |
| `testData()`, `TestData` | Seeded, reproducible fake data. A failure prints the seed. |
| `temporaryDirectory()`, `Sandbox` | Self-cleaning temp dirs, and temporary env/ini settings and output capture that are always restored. |
| `assertUniqueElements` | Duplicate check that names the keys. |

## Built for AI coding agents

<!-- tokens:section -->
<!-- prettier-ignore-start -->
An agent that knows these helpers writes one call where it would otherwise
write the loop, the timer, the statistics and the failure message, and then
read all of it again on every later change. For the tests in the
[benchmark](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/RESULTS.md), that is **676 → 296 tokens
(56% fewer)**:

| Test | Hand-written | With suggestedtests | Saved |
| --- | ---: | ---: | ---: |
| Performance budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/performance.without.php), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/performance.with.php)) | 219 | 76 | 65% |
| Wait for a condition ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/eventually.without.php), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/eventually.with.php)) | 119 | 69 | 42% |
| Peak-RSS budget ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/memory.without.php), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/memory.with.php)) | 130 | 89 | 32% |
| Temporary env var ([without](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/env_sandbox.without.php), [with](https://github.com/lesterkaufungen/suggestedtests/blob/main/bench/tokens/php/env_sandbox.with.php)) | 208 | 62 | 70% |

Estimated with the public `o200k_base` tokenizer: other models count
differently, so compare the ratios, not the numbers. Reasoning and retries
aren't counted, and the hand-written versions are often weaker (Linux-only
memory reads, no seed in the failure).

Tell your agent the helpers exist. Paste this into `CLAUDE.md`, `AGENTS.md`
or your editor's rules (212 tokens of context, paid back after about
3 tests):

````markdown
## Tests: use `suggestedtests` (`use SuggestedTests\PHPUnit\SuggestedTests;` in the test class)

- Timing budgets: `$this->assertPerformance(fn () => ..., budgetMs: 5)`; statistics: `Benchmark::run('name', fn () => ...)`.
- Never `sleep()`: `$this->assertEventually(fn () => $this->assert...(...))`.
- Memory: `$this->assertMemory(fn () => ..., maxHeapGrowth: 1 * Memory::MiB)` or `maxPeakGrowth:` for RSS.
- Isolation: `Sandbox::withEnv([...], fn)`, `Sandbox::withIni([...], fn)`, `Sandbox::captureOutput(fn)`, `$this->temporaryDirectory()`.
- Given/when/then: `$this->scenario(function (Steps $s) {...})`; spies: `new Spy()` + `assertSpyCalledWith`; snapshots: `assertMatchesSnapshot`.
- Seeded data: `$this->testData()`; duplicates: `assertUniqueElements`.
````
<!-- prettier-ignore-end -->
<!-- /tokens:section -->

## Install

```sh
composer require --dev lesterkaufungen/suggestedtests
```

Requires PHP 7.4+ (64-bit for `TestData`) and, for the trait, PHPUnit 9.6 to 12.
The native bridge needs
`ext-ffi`, which is enabled for the CLI by default (`ffi.enable=preload`).
Without it, everything except RSS and CPU time keeps working.

The examples use named arguments, which need PHP 8. On PHP 7.4, pass the
same arguments by position: `$this->assertPerformance($fn, 5)`.

```php
use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;

final class CartTest extends TestCase
{
    use SuggestedTests;
}
```

## Performance budgets

```php
public function testParsingStaysFast(): void
{
    $this->assertPerformance(fn () => $parser->parse($bigJson), budgetMs: 5);
}

public function testReport(): void
{
    echo Benchmark::run('sort', fn () => sort($data), iterations: 50);
    // sort: n=50 min=1.02ms median=1.10ms mean=1.15ms p95=1.40ms max=2.01ms ±0.12ms
}
```

The budget is checked against the median by default, which is robust against
GC pauses. Pass `statistic: Statistic::P95` (or `Min`, `Mean`, `Max`) to
check something else. Pass `clock: Clock::Cpu` to measure CPU time, which
ignores `sleep`, I/O waits and other processes.

## Memory budgets

```php
$this->assertMemory(fn () => $importer->run($file), maxHeapGrowth: 1 * Memory::MiB);
$this->assertMemory(fn () => $image->resize(4000, 4000), maxPeakGrowth: 64 * Memory::MiB);
```

`maxHeapGrowth` and `maxHeapPeakGrowth` use PHP's own allocator
(`memory_get_usage`). They are exact and always available.
`maxHeapPeakGrowth` needs PHP 8.2+ (`memory_reset_peak_usage`). `maxRssGrowth`
and `maxPeakGrowth` use the native bridge. They see memory
that PHP's heap doesn't, such as GD and Imagick images, libxml documents and
FFI buffers.

## Native bridge (Windows / Linux / macOS)

```php
SystemProbe::processCpuTime();  // CpuTime(user: 1.25s, system: 80.00ms)
SystemProbe::threadCpuTimeNs();
SystemProbe::memoryUsage();     // MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)
SystemProbe::cpuCount();
```

**You don't need Rust or a compiler.** The package ships the bridge prebuilt
for Linux (glibc ≥ 2.17 and musl; x64, arm64, x86, ARMv7 and RISC-V 64), macOS (Intel and Apple Silicon) and Windows (x64, arm64, x86), and Android (Termux). It is loaded with `FFI::cdef`. To use your own build, point
`$SUGGESTEDTESTS_NATIVE_LIB` at it. Call `$this->requireNativeBridge()` to
skip a test, with the reason, where the bridge is unavailable.

### Startup report

The bridge can describe the machine the tests run on: OS, architecture, C
library, container, VM and machine kind, as three `suggestedtests: ...` lines on
stderr. It is off by default, so nothing is printed. Turn it on for the whole
run, which prints it as the bridge loads:

```sh
SUGGESTEDTESTS_VERBOSE=1 vendor/bin/phpunit
```

Composer's autoloader loads the bridge (on the command line), so the report appears in every PHPUnit run, even one that never calls a native helper. Or turn it on from code, which prints it then (at most once per process):

```php
SystemProbe::setVerbose(true);
```

```
suggestedtests: native bridge loaded (ABI v1)
suggestedtests: platform: linux x86_64 glibc 2.39, 64-bit, os 6.8.0-45-generic
suggestedtests: environment: server, container docker, vm kvm (KVMKVMKVM), flags: ci
```

This flag controls nothing else.

## `assertEventually`: no more fixed sleeps

```php
$this->assertEventually(fn () => $this->assertFileExists($exportPath));
$job = $this->assertEventually(function () use ($queue) {
    $this->assertNotNull($job = $queue->finished());
    return $job;
}, timeoutMs: 10_000, intervalMs: 100);
```

## Given / when / then

```php
$this->scenario(function (Steps $s) {
    $cart = null;
    $s->given('an empty cart', function () use (&$cart) { $cart = new Cart(); });
    $s->when('two items are added', function () use (&$cart) { $cart->add(10)->add(20); });
    $s->then('the total is 30', function () use (&$cart) { $this->assertSame(30, $cart->total()); });
});
// Then: the total is 30
// Failed asserting that 20 is identical to 30.
```

The failure keeps its original class, so PHPUnit still reports a failure (with
its diff), not an error. Only the step is prepended to the message.

## Spies

```php
$onSaved = new Spy();                     // or new Spy(fn (User $u) => $u->id)
$form->onSaved($onSaved);
$form->submit();

$this->assertSpyCalledTimes($onSaved, 1);
$this->assertSpyCalledWith($onSaved, [$this->isInstanceOf(User::class)]);
$onSaved->lastCall();                     // [User]
```

## Snapshots

```php
$this->assertMatchesSnapshot($renderer->render($invoice));
$this->assertMatchesSnapshot($api->toArray()); // arrays and objects are stored as JSON
```

The first run writes `__snapshots__/<TestClass>/<testName>.txt` next to the
test. In CI (when `$CI` is set), a missing snapshot fails instead of being
written. To accept intentional changes, run with
`SUGGESTEDTESTS_UPDATE_SNAPSHOTS=1`.

## Reproducible test data

```php
$data = $this->testData();
$user = new User(name: $data->word(), email: $data->email(), age: $data->integer(18, 90));
```

Each test gets a fresh seed. When a test fails, the seed is printed
(`suggestedtests: CartTest::testCheckout used TestData seed 1804289383;
reproduce with SUGGESTEDTESTS_SEED=1804289383`). Use `new TestData(42)`
directly anywhere else.

## Sandbox

```php
Sandbox::withEnv(['APP_ENV' => 'production'], fn () => $this->assertTrue(isProduction()));
Sandbox::withIni(['precision' => 5], fn () => ...);
$html = Sandbox::captureOutput(fn () => $view->render());
$dir = $this->temporaryDirectory(); // removed after the test
```

## Example

See [`examples/ExampleTest.php`](examples/ExampleTest.php). Run it with
`vendor/bin/phpunit examples`.

## License

MIT
