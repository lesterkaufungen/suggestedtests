<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Helpers for the oldest supported PHP (7.4).
 *
 * @internal
 */
final class Compat
{
    public static function startsWith(string $haystack, string $needle): bool
    {
        return strncmp($haystack, $needle, strlen($needle)) === 0;
    }

    public static function contains(string $haystack, string $needle): bool
    {
        return $needle === '' || strpos($haystack, $needle) !== false;
    }

    /** get_debug_type() of PHP 8. */
    public static function typeOf($value): string
    {
        return is_object($value) ? get_class($value) : gettype($value);
    }
}
