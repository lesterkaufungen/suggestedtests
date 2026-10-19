<?php

use PHPUnit\Framework\TestCase;

final class ImporterTest extends TestCase
{
    public function testImportStaysSmall(): void
    {
        $before = getrusage()['ru_maxrss'];
        $this->importer->run($this->file);
        $growthKiB = getrusage()['ru_maxrss'] - $before;
        $this->assertLessThanOrEqual(50 * 1024, $growthKiB, sprintf(
            'peak RSS grew by %.1f MiB > 50 MiB',
            $growthKiB / 1024
        ));
    }
}
