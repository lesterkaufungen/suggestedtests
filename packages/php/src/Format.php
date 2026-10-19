<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Human readable sizes and durations used in failure messages. */
final class Format
{
    /** Formats a byte count, e.g. `12.5 MiB`. */
    public static function bytes(int $bytes): string
    {
        $units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        $value = abs($bytes);
        $unit = 0;
        while ($value >= 1024 && $unit < count($units) - 1) {
            $value /= 1024;
            $unit++;
        }
        if ($unit === 0) {
            return "$bytes B";
        }
        return ($bytes < 0 ? '-' : '') . number_format($value, 1, '.', '') . ' ' . $units[$unit];
    }

    /** Formats milliseconds as `850µs`, `1.25ms` or `2.00s`. */
    public static function ms(float $ms): string
    {
        if (abs($ms) < 1) {
            return round($ms * 1000) . 'µs';
        }
        if (abs($ms) < 1000) {
            return number_format($ms, 2, '.', '') . 'ms';
        }
        return number_format($ms / 1000, 2, '.', '') . 's';
    }
}
