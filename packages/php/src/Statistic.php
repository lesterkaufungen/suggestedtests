<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Which statistic of a {@see BenchmarkResult} a budget is checked against.
 * Constants rather than an enum, so the package runs on PHP 7.4.
 */
final class Statistic
{
    /** Fastest sample. */
    public const Min = 'min';
    /** Arithmetic mean of all samples. */
    public const Mean = 'mean';
    /** Middle sample. Robust against GC pauses; the default. */
    public const Median = 'median';
    /** 95th percentile sample. */
    public const P95 = 'p95';
    /** Slowest sample. */
    public const Max = 'max';

    private function __construct()
    {
    }

    /** @return list<string> */
    public static function all(): array
    {
        return [self::Min, self::Mean, self::Median, self::P95, self::Max];
    }

    /** @throws \InvalidArgumentException for an unknown statistic */
    public static function check(string $statistic): string
    {
        if (!in_array($statistic, self::all(), true)) {
            throw new \InvalidArgumentException("statistic must be one of " . implode(', ', self::all()) . ", got '$statistic'");
        }
        return $statistic;
    }
}
