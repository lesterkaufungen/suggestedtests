<?php

use PHPUnit\Framework\TestCase;
use SuggestedTests\Sandbox;

final class ConfigTest extends TestCase
{
    public function testProductionMode(): void
    {
        Sandbox::withEnv(['APP_ENV' => 'production'], fn () => $this->assertTrue(isProduction()));
    }
}
