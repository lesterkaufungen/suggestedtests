<?php

use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;

final class ExportTest extends TestCase
{
    use SuggestedTests;

    public function testExportFinishes(): void
    {
        $this->assertEventually(fn () => $this->assertFileExists($this->exportPath));
    }
}
