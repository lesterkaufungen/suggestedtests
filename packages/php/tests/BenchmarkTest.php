<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use SuggestedTests\Benchmark;
use SuggestedTests\BenchmarkResult;
use SuggestedTests\Clock;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Statistic;

final class BenchmarkTest extends TestCase
{
    use SuggestedTests;

    public function testStatistics(): void
    {
        $r = new BenchmarkResult('r', [5.0, 1.0, 3.0, 2.0, 4.0]);
        $this->assertSame([1.0, 5.0, 3.0, 3.0, 5.0], [$r->min(), $r->max(), $r->mean(), $r->median(), $r->p95()]);
        $this->assertSame(3.0, $r->get(Statistic::Median));
        $this->assertSame(1.0, $r->percentile(0));
        $this->assertEqualsWithDelta(sqrt(2), $r->stdDev(), 1e-9);
        $this->assertSame([5.0, 1.0, 3.0, 2.0, 4.0], $r->samples);
    }

    public function testResultValidates(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        new BenchmarkResult('r', []);
    }

    public function testPercentileValidates(): void
    {
        $this->expectException(\OutOfRangeException::class);
        (new BenchmarkResult('r', [1.0]))->percentile(101);
    }

    public function testToString(): void
    {
        $this->assertStringStartsWith('x: n=3 min=500µs median=2.50ms mean=1.00s', (string) new BenchmarkResult('x', [0.5, 2.5, 3000.0]));
    }

    public function testRunCountsCalls(): void
    {
        $calls = 0;
        $r = Benchmark::run('b', function () use (&$calls) {
            $calls++;
        }, 5, 2);
        $this->assertSame(7, $calls);
        $this->assertCount(5, $r->samples);
    }

    /** @return iterable<string, array{int, int}> */
    public static function badCounts(): iterable
    {
        yield 'no iterations' => [0, 0];
        yield 'negative warmup' => [1, -1];
    }

    /** @dataProvider badCounts */
    #[DataProvider('badCounts')]
    public function testRunValidatesCounts(int $iterations, int $warmup): void
    {
        $this->expectException(\OutOfRangeException::class);
        Benchmark::run('b', fn () => null, $iterations, $warmup);
    }

    public function testCpuClockIgnoresSleep(): void
    {
        $this->requireNativeBridge();
        $r = Benchmark::run('sleep', fn () => usleep(10_000), 3, 0, Clock::Cpu);
        $this->assertSame(Clock::Cpu, $r->clock);
        $this->assertLessThan(5, $r->median());
    }

    public function testAssertPerformancePasses(): void
    {
        $this->assertSame('benchmark', $this->assertPerformance(fn () => null, 1000)->name);
    }

    public function testAssertPerformanceFailsAsFailure(): void
    {
        try {
            $this->assertPerformance(fn () => str_repeat('x', 100_000), 0, Statistic::Max, 2, 3, 'repeat');
        } catch (AssertionFailedError $e) {
            // Counted although it failed, or PHPUnit also reports the test as risky.
            $this->assertSame(1, method_exists($this, 'numberOfAssertionsPerformed')
                ? $this->numberOfAssertionsPerformed()
                : $this->getNumAssertions()); // PHPUnit 9
            $this->assertMatchesRegularExpression('/^Performance budget exceeded: max .* > budget 0µs\nrepeat: n=2/', $e->getMessage());
            return;
        }
        $this->fail('expected a failure');
    }

    public function testNegativeBudgetIsRejected(): void
    {
        $this->expectException(\OutOfRangeException::class);
        Benchmark::expect(fn () => null, -1);
    }
}
