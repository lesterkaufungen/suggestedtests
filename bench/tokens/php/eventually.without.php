<?php

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\TestCase;

final class ExportTest extends TestCase
{
    public function testExportFinishes(): void
    {
        $deadline = microtime(true) + 5;
        while (true) {
            try {
                $this->assertFileExists($this->exportPath);
                return;
            } catch (AssertionFailedError $e) {
                if (microtime(true) >= $deadline) {
                    throw $e;
                }
                usleep(20000);
            }
        }
    }
}
