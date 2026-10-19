<?php

use PHPUnit\Framework\TestCase;

final class ConfigTest extends TestCase
{
    public function testProductionMode(): void
    {
        $saved = [getenv('APP_ENV'), $_ENV['APP_ENV'] ?? null, $_SERVER['APP_ENV'] ?? null];
        putenv('APP_ENV=production');
        $_ENV['APP_ENV'] = $_SERVER['APP_ENV'] = 'production';
        try {
            $this->assertTrue(isProduction());
        } finally {
            [$env, $envArray, $server] = $saved;
            putenv($env === false ? 'APP_ENV' : "APP_ENV=$env");
            if ($envArray === null) {
                unset($_ENV['APP_ENV']);
            } else {
                $_ENV['APP_ENV'] = $envArray;
            }
            if ($server === null) {
                unset($_SERVER['APP_ENV']);
            } else {
                $_SERVER['APP_ENV'] = $server;
            }
        }
    }
}
