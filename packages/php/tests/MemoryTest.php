<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\TestCase;
use SuggestedTests\Memory;
use SuggestedTests\MemoryReport;
use SuggestedTests\MemoryUsage;
use SuggestedTests\PHPUnit\SuggestedTests;

final class MemoryTest extends TestCase
{
    use SuggestedTests;

    public function testReport(): void
    {
        $r = new MemoryReport(new MemoryUsage(10, 20), new MemoryUsage(15, 30), -50, 100);
        $this->assertSame([5, 10], [$r->rssGrowthBytes(), $r->peakGrowthBytes()]);
        $this->assertSame('MemoryReport(heap: -50 B, heap peak: +100 B, rss: +5 B, rss peak: +10 B)', (string) $r);
        $this->assertNull((new MemoryReport(null, null, 0, 0))->rssGrowthBytes());
        $this->assertSame('MemoryReport(heap: +0 B, heap peak: n/a, rss: n/a, rss peak: n/a)', (string) new MemoryReport(null, null, 0, null));
    }

    public function testHeapGrowthIsMeasured(): void
    {
        $keep = [];
        $report = Memory::measure(function () use (&$keep) {
            $keep = range(1, 100_000);
        });
        $this->assertGreaterThan(1024 * 1024, $report->heapGrowthBytes);
        $this->assertCount(100_000, $keep);
    }

    public function testHeapPeakCountsTemporaryMemory(): void
    {
        if (!Memory::canMeasureHeapPeak()) {
            $this->markTestSkipped('needs memory_reset_peak_usage() (PHP 8.2+)');
        }
        $report = Memory::measure(function () {
            $tmp = str_repeat('x', 4 * Memory::MiB);
            unset($tmp);
        });
        $this->assertGreaterThanOrEqual(4 * Memory::MiB, $report->heapPeakGrowthBytes);
        $this->assertLessThan(Memory::MiB, $report->heapGrowthBytes);
    }

    public function testHeapBudgetFails(): void
    {
        $keep = [];
        $this->expectException(AssertionFailedError::class);
        $this->expectExceptionMessage('Memory budget exceeded: PHP heap grew');
        $this->assertMemory(function () use (&$keep) {
            $keep = range(1, 100_000);
        }, 1024);
    }

    public function testRssBudgetFails(): void
    {
        $this->requireNativeBridge();
        $keep = '';
        $this->expectException(AssertionFailedError::class);
        $this->expectExceptionMessage('peak RSS grew');
        $this->assertMemory(function () use (&$keep) {
            $keep = str_repeat('x', 256 * Memory::MiB);
        }, null, null, null, 0);
    }

    public function testBudgetsAreValidated(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Memory::expect(fn () => null);
    }

    public function testHeapPeakBudgetNeedsPhp82(): void
    {
        if (Memory::canMeasureHeapPeak()) {
            $this->assertInstanceOf(MemoryReport::class, Memory::expect(fn () => null, null, 1024));
            return;
        }
        $this->expectException(\LogicException::class);
        Memory::expect(fn () => null, null, 1024);
    }

    public function testNegativeBudgetIsRejected(): void
    {
        $this->expectException(\OutOfRangeException::class);
        Memory::expect(fn () => null, -1);
    }
}
