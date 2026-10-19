<?php

use PHPUnit\Framework\TestCase;
use SuggestedTests\Memory;
use SuggestedTests\PHPUnit\SuggestedTests;

final class ImporterTest extends TestCase
{
    use SuggestedTests;

    public function testImportStaysSmall(): void
    {
        $this->assertMemory(fn () => $this->importer->run($this->file), maxPeakGrowth: 50 * Memory::MiB);
    }
}
