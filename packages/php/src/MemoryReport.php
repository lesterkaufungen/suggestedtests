<?php

declare(strict_types=1);

namespace SuggestedTests;

/** How memory changed while running a body with {@see Memory::measure()}. */
final class MemoryReport
{
    /** @var ?MemoryUsage Native RSS sample before the body (null without the bridge). */
    public $before;
    /** @var ?MemoryUsage Native RSS sample after the body (null without the bridge). */
    public $after;
    /** @var int Change of PHP's heap (`memory_get_usage()`). */
    public $heapGrowthBytes;
    /** @var ?int Highest extra PHP heap while the body ran; null before PHP 8.2. */
    public $heapPeakGrowthBytes;

    public function __construct(?MemoryUsage $before, ?MemoryUsage $after, int $heapGrowthBytes, ?int $heapPeakGrowthBytes)
    {
        $this->before = $before;
        $this->after = $after;
        $this->heapGrowthBytes = $heapGrowthBytes;
        $this->heapPeakGrowthBytes = $heapPeakGrowthBytes;
    }

    /** Change in resident memory, or null without the native bridge. */
    public function rssGrowthBytes(): ?int
    {
        return $this->before === null || $this->after === null
            ? null
            : $this->after->currentRssBytes - $this->before->currentRssBytes;
    }

    /** How far the body pushed the process' peak RSS up, or null without the native bridge. */
    public function peakGrowthBytes(): ?int
    {
        return $this->before === null || $this->after === null
            ? null
            : $this->after->peakRssBytes - $this->before->peakRssBytes;
    }

    private static function signed(?int $bytes): string
    {
        return $bytes === null ? 'n/a' : ($bytes >= 0 ? '+' : '') . Format::bytes($bytes);
    }

    public function __toString(): string
    {
        return sprintf(
            'MemoryReport(heap: %s, heap peak: %s, rss: %s, rss peak: %s)',
            self::signed($this->heapGrowthBytes),
            self::signed($this->heapPeakGrowthBytes),
            self::signed($this->rssGrowthBytes()),
            self::signed($this->peakGrowthBytes())
        );
    }
}
