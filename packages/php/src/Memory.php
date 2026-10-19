<?php

declare(strict_types=1);

namespace SuggestedTests;

use SuggestedTests\Native\Bridge;

/**
 * Memory budgets. PHP's own heap (`memory_get_usage`) is exact and always
 * available; process RSS comes from the native bridge and also covers
 * memory held by extensions (images, XML, FFI).
 */
final class Memory
{
    /** Bytes in a kibibyte. */
    public const KiB = 1024;
    /** Bytes in a mebibyte. */
    public const MiB = 1024 * 1024;
    /** Bytes in a gibibyte. */
    public const GiB = 1024 * 1024 * 1024;

    private function __construct()
    {
    }

    /** Whether the heap peak can be measured per body (`memory_reset_peak_usage`, PHP 8.2+). */
    public static function canMeasureHeapPeak(): bool
    {
        return function_exists('memory_reset_peak_usage');
    }

    /** Runs `$body` and reports how memory changed. */
    public static function measure(callable $body): MemoryReport
    {
        $native = SystemProbe::isAvailable();
        gc_collect_cycles();
        $before = $native ? SystemProbe::memoryUsage() : null;
        $heapBefore = memory_get_usage();
        $peak = self::canMeasureHeapPeak();
        if ($peak) {
            memory_reset_peak_usage();
        }
        $body();
        $heapPeak = $peak ? memory_get_peak_usage() : null;
        gc_collect_cycles();
        $heapAfter = memory_get_usage();
        return new MemoryReport(
            $before,
            $native ? SystemProbe::memoryUsage() : null,
            $heapAfter - $heapBefore,
            $heapPeak === null ? null : max(0, $heapPeak - $heapBefore)
        );
    }

    /**
     * Runs `$body` and fails if memory grew more than the given budgets (in
     * bytes; null means no limit). At least one is required. RSS budgets need
     * the native bridge; `$maxHeapPeakGrowth` needs PHP 8.2.
     *
     * ```php
     * Memory::expect(fn () => $repository->loadAll(), 1 * Memory::MiB);
     * Memory::expect(fn () => $image->resize(), maxPeakGrowth: 64 * Memory::MiB); // PHP 8
     * ```
     */
    public static function expect(
        callable $body,
        ?int $maxHeapGrowth = null,
        ?int $maxHeapPeakGrowth = null,
        ?int $maxRssGrowth = null,
        ?int $maxPeakGrowth = null
    ): MemoryReport {
        $budgets = [
            'maxHeapGrowth' => $maxHeapGrowth,
            'maxHeapPeakGrowth' => $maxHeapPeakGrowth,
            'maxRssGrowth' => $maxRssGrowth,
            'maxPeakGrowth' => $maxPeakGrowth,
        ];
        if (array_filter($budgets, static function ($b): bool {
            return $b !== null;
        }) === []) {
            throw new \InvalidArgumentException('Provide at least one of: ' . implode(', ', array_keys($budgets)) . '.');
        }
        foreach ($budgets as $name => $value) {
            if ($value !== null && $value < 0) {
                throw new \OutOfRangeException("$name must be >= 0, got $value");
            }
        }
        if ($maxHeapPeakGrowth !== null && !self::canMeasureHeapPeak()) {
            throw new \LogicException('maxHeapPeakGrowth needs memory_reset_peak_usage() (PHP 8.2+)');
        }
        if (($maxRssGrowth !== null || $maxPeakGrowth !== null) && !SystemProbe::isAvailable()) {
            throw new NativeBridgeException('memoryUsage', Bridge::ERR_UNSUPPORTED, SystemProbe::skipReason());
        }
        $report = self::measure($body);
        $checks = [
            [$maxHeapGrowth, $report->heapGrowthBytes, 'PHP heap grew'],
            [$maxHeapPeakGrowth, $report->heapPeakGrowthBytes, 'PHP heap peak grew'],
            [$maxRssGrowth, $report->rssGrowthBytes(), 'RSS grew'],
            [$maxPeakGrowth, $report->peakGrowthBytes(), 'peak RSS grew'],
        ];
        foreach ($checks as [$limit, $actual, $what]) {
            if ($limit !== null && $actual !== null && $actual > $limit) {
                Failure::raise(sprintf(
                    "Memory budget exceeded: %s %s > budget %s\n%s",
                    $what,
                    Format::bytes($actual),
                    Format::bytes($limit),
                    $report
                ));
            }
        }
        return $report;
    }
}
