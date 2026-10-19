<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Benchmarks and performance budgets. */
final class Benchmark
{
    private function __construct()
    {
    }

    private static function checkCounts(int $iterations, int $warmup): void
    {
        if ($iterations < 1) {
            throw new \OutOfRangeException("iterations must be >= 1, got $iterations");
        }
        if ($warmup < 0) {
            throw new \OutOfRangeException("warmup must be >= 0, got $warmup");
        }
    }

    /** @return \Closure(): int nanoseconds */
    private static function reader(string $clock): \Closure
    {
        if (Clock::check($clock) === Clock::Wall) {
            return static function (): int {
                return hrtime(true);
            };
        }
        if (!SystemProbe::isAvailable()) {
            throw new \LogicException('Clock::Cpu needs the native bridge: ' . SystemProbe::skipReason());
        }
        return \Closure::fromCallable([SystemProbe::class, 'threadCpuTimeNs']);
    }

    /**
     * Runs `$body` `$warmup` times untimed, then `$iterations` times timed.
     *
     * ```php
     * $result = Benchmark::run('parse', fn () => json_decode($payload));
     * echo $result; // parse: n=20 min=1.02ms median=1.10ms ...
     * ```
     *
     * @param string $clock A {@see Clock} constant.
     */
    public static function run(
        string $name,
        callable $body,
        int $iterations = 20,
        int $warmup = 3,
        string $clock = Clock::Wall
    ): BenchmarkResult {
        self::checkCounts($iterations, $warmup);
        $now = self::reader($clock);
        for ($i = 0; $i < $warmup; $i++) {
            $body();
        }
        $samples = [];
        for ($i = 0; $i < $iterations; $i++) {
            $start = $now();
            $body();
            $samples[] = ($now() - $start) / 1e6;
        }
        return new BenchmarkResult($name, $samples, $clock);
    }

    /**
     * Benchmarks `$body` and fails if `$statistic` exceeds `$budgetMs`.
     *
     * ```php
     * Benchmark::expect(fn () => parse($bigJson), 5.0);
     * Benchmark::expect(fn () => render(), budgetMs: 20, statistic: Statistic::P95); // PHP 8
     * ```
     *
     * @param string $statistic A {@see Statistic} constant.
     * @param string $clock A {@see Clock} constant.
     */
    public static function expect(
        callable $body,
        float $budgetMs,
        string $statistic = Statistic::Median,
        int $iterations = 20,
        int $warmup = 3,
        string $name = 'benchmark',
        string $clock = Clock::Wall
    ): BenchmarkResult {
        if ($budgetMs < 0) {
            throw new \OutOfRangeException("budgetMs must be >= 0, got $budgetMs");
        }
        Statistic::check($statistic);
        Clock::check($clock);
        self::checkCounts($iterations, $warmup);
        $result = self::run($name, $body, $iterations, $warmup, $clock);
        $actual = $result->get($statistic);
        if ($actual > $budgetMs) {
            Failure::raise(sprintf(
                "Performance budget exceeded: %s %s > budget %s\n%s",
                $statistic,
                Format::ms($actual),
                Format::ms($budgetMs),
                $result
            ));
        }
        return $result;
    }
}
