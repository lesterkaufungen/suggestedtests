<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Resident memory (RSS / working set) of the process, in bytes. */
final class MemoryUsage
{
    /** @var int Memory currently resident in RAM. */
    public $currentRssBytes;
    /** @var int Highest resident memory since the process started. */
    public $peakRssBytes;

    public function __construct(int $currentRssBytes, int $peakRssBytes)
    {
        $this->currentRssBytes = $currentRssBytes;
        $this->peakRssBytes = $peakRssBytes;
    }

    public function __toString(): string
    {
        return sprintf('MemoryUsage(current: %s, peak: %s)', Format::bytes($this->currentRssBytes), Format::bytes($this->peakRssBytes));
    }
}
