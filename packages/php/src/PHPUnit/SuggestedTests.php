<?php

declare(strict_types=1);

namespace SuggestedTests\PHPUnit;

use PHPUnit\Framework\Attributes\After;
use PHPUnit\Framework\Constraint\Constraint;
use SuggestedTests\Assert;
use SuggestedTests\Benchmark;
use SuggestedTests\BenchmarkResult;
use SuggestedTests\Clock;
use SuggestedTests\Eventually;
use SuggestedTests\Memory;
use SuggestedTests\MemoryReport;
use SuggestedTests\Sandbox;
use SuggestedTests\Snapshot;
use SuggestedTests\Spy;
use SuggestedTests\Statistic;
use SuggestedTests\Steps;
use SuggestedTests\SystemProbe;
use SuggestedTests\TestData;

/**
 * Adds suggestedtests helpers to a PHPUnit `TestCase` (PHPUnit 9.6 to 12,
 * PHP 7.4+):
 *
 * ```php
 * final class CartTest extends TestCase
 * {
 *     use SuggestedTests;
 *
 *     public function testTotalIsFast(): void
 *     {
 *         $this->assertPerformance(fn () => (new Cart())->total(), 1.0);
 *     }
 * }
 * ```
 *
 * Temporary directories are deleted after each test. When a test that used
 * `testData()` fails, its seed is printed; set `SUGGESTEDTESTS_SEED` to rerun
 * with it.
 *
 * @phpstan-require-extends \PHPUnit\Framework\TestCase
 */
trait SuggestedTests
{
    /** @var list<string> */
    private $suggestedTestsTempDirs = [];
    /** @var ?TestData */
    private $suggestedTestsData = null;
    /** @var array<string, int> */
    private $suggestedTestsSnapshotCounts = [];

    /** Skips the test (with the reason) unless the native bridge is available. */
    protected function requireNativeBridge(): void
    {
        if (!SystemProbe::isAvailable()) {
            $this->markTestSkipped((string) SystemProbe::skipReason());
        }
    }

    /**
     * Seeded test data: random per test, or `$SUGGESTEDTESTS_SEED`. The same
     * instance is returned for the rest of the test.
     */
    protected function testData(): TestData
    {
        if ($this->suggestedTestsData === null) {
            $env = getenv('SUGGESTEDTESTS_SEED');
            $seed = is_string($env) && $env !== '' ? (int) $env : random_int(0, (1 << 31) - 1);
            $this->suggestedTestsData = new TestData($seed);
        }
        return $this->suggestedTestsData;
    }

    /** The test method's name, on every PHPUnit version. */
    private function suggestedTestsName(): string
    {
        return method_exists($this, 'name') ? $this->name() : $this->getName(false);
    }

    /** Whether the current test failed or errored, on every PHPUnit version. */
    private function suggestedTestsFailed(): bool
    {
        if (method_exists($this, 'status')) { // PHPUnit 10+
            $status = $this->status();
            return $status->isFailure() || $status->isError();
        }
        return $this->hasFailed(); // PHPUnit 9
    }

    /** Runs the given/when/then steps declared by `$declare`. */
    protected function scenario(callable $declare): void
    {
        $steps = new Steps();
        $declare($steps);
        $steps->run();
    }

    /**
     * See {@see Eventually::until()}.
     *
     * @return mixed
     */
    protected function assertEventually(callable $body, float $timeoutMs = 5000, float $intervalMs = 20)
    {
        $this->addToAssertionCount(1); // before, as PHPUnit's assertions do: a failure isn't also "risky"
        $result = Eventually::until($body, $timeoutMs, $intervalMs);
        return $result;
    }

    /** See {@see Benchmark::expect()}. */
    protected function assertPerformance(
        callable $body,
        float $budgetMs,
        string $statistic = Statistic::Median,
        int $iterations = 20,
        int $warmup = 3,
        string $name = 'benchmark',
        string $clock = Clock::Wall
    ): BenchmarkResult {
        $this->addToAssertionCount(1);
        $result = Benchmark::expect($body, $budgetMs, $statistic, $iterations, $warmup, $name, $clock);
        return $result;
    }

    /** See {@see Memory::expect()}. */
    protected function assertMemory(
        callable $body,
        ?int $maxHeapGrowth = null,
        ?int $maxHeapPeakGrowth = null,
        ?int $maxRssGrowth = null,
        ?int $maxPeakGrowth = null
    ): MemoryReport {
        $this->addToAssertionCount(1);
        $report = Memory::expect($body, $maxHeapGrowth, $maxHeapPeakGrowth, $maxRssGrowth, $maxPeakGrowth);
        return $report;
    }

    /**
     * See {@see Assert::unique()}.
     *
     * @param iterable<mixed> $items
     */
    protected function assertUniqueElements(iterable $items): void
    {
        $this->addToAssertionCount(1);
        Assert::unique($items);
    }

    /** Asserts that `$spy` was called at least once. */
    protected function assertSpyCalled(Spy $spy): void
    {
        $this->assertTrue($spy->called(), 'Expected the spy to be called, but it never was.');
    }

    /** Asserts that `$spy` was never called. */
    protected function assertSpyNotCalled(Spy $spy): void
    {
        $this->assertSpyCalledTimes($spy, 0);
    }

    /** Asserts that `$spy` was called exactly `$times` times. */
    protected function assertSpyCalledTimes(Spy $spy, int $times): void
    {
        $this->assertCount($times, $spy, "Expected the spy to be called $times time(s). $spy");
    }

    /**
     * Asserts that `$spy` has a call whose arguments match `$args`. Each
     * element is a value (compared with `==` like assertEquals) or a
     * PHPUnit constraint such as `$this->greaterThan(0)`.
     *
     * @param list<mixed> $args
     */
    protected function assertSpyCalledWith(Spy $spy, array $args): void
    {
        foreach ($spy->calls() as $call) {
            if (count($call) !== count($args)) {
                continue;
            }
            foreach ($args as $i => $expected) {
                $constraint = $expected instanceof Constraint ? $expected : $this->equalTo($expected);
                if (!$constraint->evaluate($call[$i], '', true)) {
                    continue 2;
                }
            }
            $this->addToAssertionCount(1);
            return;
        }
        $described = array_map(static function ($a) {
            return $a instanceof Constraint ? $a->toString() : $a;
        }, $args);
        $this->fail(sprintf(
            'Expected the spy to be called with %s, but it was called %d time(s): %s',
            json_encode($described),
            count($spy),
            $spy
        ));
    }

    /**
     * Compares `$value` with the snapshot `__snapshots__/<TestClass>/<test>[_<n>].txt`
     * next to the test file. See {@see Snapshot} for creating and updating them.
     *
     * @param mixed $value
     */
    protected function assertMatchesSnapshot($value, ?string $name = null): void
    {
        $class = new \ReflectionClass($this);
        $test = $this->suggestedTestsName();
        $data = method_exists($this, 'dataName') ? (string) $this->dataName() : '';
        if ($data !== '') {
            $test .= '_' . $data;
        }
        if ($name === null) {
            $n = ($this->suggestedTestsSnapshotCounts[$test] ?? 0) + 1;
            $this->suggestedTestsSnapshotCounts[$test] = $n;
            $name = $n === 1 ? $test : "{$test}_$n";
        }
        $safe = preg_replace('/[^A-Za-z0-9_.-]+/', '_', $name);
        $path = dirname((string) $class->getFileName()) . '/__snapshots__/' . $class->getShortName() . "/$safe.txt";
        $this->addToAssertionCount(1);
        $created = Snapshot::assertMatches($value, $path);
        if ($created) {
            fwrite(STDERR, "\nsuggestedtests: wrote snapshot $path\n");
        }
    }

    /** An empty directory that is deleted after the test. */
    protected function temporaryDirectory(): string
    {
        $dir = Sandbox::temporaryDirectory();
        $this->suggestedTestsTempDirs[] = $dir;
        return $dir;
    }

    /**
     * Deletes the test's temporary directories and prints the TestData seed
     * of a failed test.
     *
     * @after
     * @internal
     */
    #[After]
    protected function suggestedTestsCleanUp(): void
    {
        foreach ($this->suggestedTestsTempDirs as $dir) {
            Sandbox::removeDirectory($dir);
        }
        $this->suggestedTestsTempDirs = [];
        if ($this->suggestedTestsData !== null && $this->suggestedTestsFailed()) {
            $seed = $this->suggestedTestsData->seed;
            fwrite(STDERR, sprintf(
                "\nsuggestedtests: %s used TestData seed %d; reproduce with SUGGESTEDTESTS_SEED=%d\n",
                static::class . '::' . $this->suggestedTestsName(),
                $seed,
                $seed
            ));
        }
        $this->suggestedTestsData = null;
    }
}
