<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * What a benchmark measures. Constants rather than an enum, so the package
 * runs on PHP 7.4.
 */
final class Clock
{
    /** Elapsed wall-clock time (`hrtime`). Includes waiting and time stolen by other processes. */
    public const Wall = 'wall';
    /** CPU time of the PHP thread, via the native bridge. Ignores waiting (I/O, sleep) and other processes. */
    public const Cpu = 'cpu';

    private function __construct()
    {
    }

    /** @throws \InvalidArgumentException for an unknown clock */
    public static function check(string $clock): string
    {
        if ($clock !== self::Wall && $clock !== self::Cpu) {
            throw new \InvalidArgumentException("clock must be 'wall' or 'cpu', got '$clock'");
        }
        return $clock;
    }
}
